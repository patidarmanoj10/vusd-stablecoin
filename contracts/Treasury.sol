// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IComet} from "./interfaces/compound/IComet.sol";
import {ICometRewards} from "./interfaces/compound/ICometRewards.sol";
import {ISwapper} from "./interfaces/bloq/ISwapper.sol";
import {IVUSD} from "./interfaces/IVUSD.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

/// @title VUSD Treasury, It stores comets and redeem those from Compound as needed.
contract Treasury is Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    string public constant NAME = "VUSD-Treasury";
    string public constant VERSION = "1.5.0";

    IVUSD public immutable vusd;
    address public redeemer;

    ISwapper public swapper = ISwapper(0x229f19942612A8dbdec3643CB23F88685CCd56A5);

    // Token => comet mapping
    mapping(address => address) public comets;
    // Token => oracle mapping
    mapping(address => address) public oracles;

    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    ICometRewards private constant COMET_REWARDS = ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);

    EnumerableSet.AddressSet private _whitelistedTokens;
    EnumerableSet.AddressSet private _cometList;
    EnumerableSet.AddressSet private _keepers;

    // Default whitelist token addresses
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // comet addresses for default whitelisted tokens
    // solhint-disable const-name-snakecase
    address private constant cUSDCv3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address private constant cUSDTv3 = 0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840;
    // solhint-enable

    // Chainlink price oracle for default whitelisted tokens
    address private constant USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private constant USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    event UpdatedRedeemer(address indexed previousRedeemer, address indexed newRedeemer);
    event UpdatedSwapper(address indexed previousSwapper, address indexed newSwapper);

    constructor(address _vusd) {
        require(_vusd != address(0), "vusd-address-is-zero");
        vusd = IVUSD(_vusd);

        _keepers.add(_msgSender());

        // Add token into the list, add oracle and comet into the mapping
        _addToken(USDC, cUSDCv3, USDC_USD);
        _addToken(USDT, cUSDTv3, USDT_USD);

        IERC20(COMP).safeApprove(address(swapper), type(uint256).max);
    }

    modifier onlyGovernor() {
        require(_msgSender() == governor(), "caller-is-not-the-governor");
        _;
    }

    modifier onlyAuthorized() {
        require(_msgSender() == governor() || _msgSender() == redeemer, "caller-is-not-authorized");
        _;
    }

    modifier onlyKeeperOrGovernor() {
        require(_msgSender() == governor() || _keepers.contains(_msgSender()), "caller-is-not-authorized");
        _;
    }

    ////////////////////////////// Only Governor //////////////////////////////
    /**
     * @notice Add token into treasury management system
     * @dev Add token address in whitelistedTokens list and add comet in mapping
     * @param _token address which we want to add in token list.
     * @param _comet comet address correspond to _token
     * @param _oracle Chainlink oracle address for token/USD feed
     */
    function addWhitelistedToken(address _token, address _comet, address _oracle) external onlyGovernor {
        require(_token != address(0), "token-address-is-zero");
        require(_comet != address(0), "comet-address-is-zero");
        require(_oracle != address(0), "oracle-address-is-zero");
        _addToken(_token, _comet, _oracle);
    }

    /**
     * @notice Remove token from treasury management system
     * @dev Removing token even if treasury has some balance of that token is intended behavior.
     * @param _token address which we want to remove from token list.
     */
    function removeWhitelistedToken(address _token) external onlyGovernor {
        require(_whitelistedTokens.remove(_token), "remove-from-list-failed");
        require(_cometList.remove(comets[_token]), "remove-from-list-failed");
        IERC20(_token).safeApprove(comets[_token], 0);
        delete comets[_token];
        delete oracles[_token];
    }

    /**
     * @notice Update redeemer address
     * @param _newRedeemer new redeemer address
     */
    function updateRedeemer(address _newRedeemer) external onlyGovernor {
        require(_newRedeemer != address(0), "redeemer-address-is-zero");
        require(redeemer != _newRedeemer, "same-redeemer");
        emit UpdatedRedeemer(redeemer, _newRedeemer);
        redeemer = _newRedeemer;
    }

    /**
     * @notice Add given address in keepers list.
     * @param _keeperAddress keeper address to add.
     */
    function addKeeper(address _keeperAddress) external onlyGovernor {
        require(_keeperAddress != address(0), "keeper-address-is-zero");
        require(_keepers.add(_keeperAddress), "add-keeper-failed");
    }

    /**
     * @notice Remove given address from keepers list.
     * @param _keeperAddress keeper address to remove.
     */
    function removeKeeper(address _keeperAddress) external onlyGovernor {
        require(_keepers.remove(_keeperAddress), "remove-keeper-failed");
    }

    /**
     * @notice Update swapper address
     * @param _swapper new swapper address
     */
    function updateSwapper(address _swapper) external onlyGovernor {
        require(_swapper != address(0), "swap-manager-address-is-zero");
        emit UpdatedSwapper(address(swapper), _swapper);

        IERC20(COMP).safeApprove(address(swapper), 0);
        IERC20(COMP).safeApprove(_swapper, type(uint256).max);
        swapper = ISwapper(_swapper);
    }

    ///////////////////////////////////////////////////////////////////////////

    /**
     * @notice Claim comp from all markets and convert to given token.
     * Also deposit those tokens to Compound
     * @param _toToken COMP will be swapped to _toToken
     * @param _minOut Minimum _toToken expected after conversion
     */
    function claimCompAndConvertTo(address _toToken, uint256 _minOut) external onlyKeeperOrGovernor {
        require(_whitelistedTokens.contains(_toToken), "token-is-not-supported");
        uint256 _len = _cometList.length();
        for (uint256 i; i < _len; i++) {
            COMET_REWARDS.claim(_cometList.at(i), address(this), true);
        }

        uint256 _compAmount = IERC20(COMP).balanceOf(address(this));
        if (_compAmount > 0) {
            swapper.swapExactInput(COMP, _toToken, _compAmount, _minOut, address(this));
        }

        uint256 _tokenAmount = IERC20(_toToken).balanceOf(address(this));
        if (_tokenAmount > 0) {
            IComet(comets[_toToken]).supply(_toToken, _tokenAmount);
        }
    }

    /**
     * @notice Migrate assets to new treasury
     * @param _newTreasury Address of new treasury of VUSD system
     */
    function migrate(address _newTreasury) external onlyGovernor {
        require(_newTreasury != address(0), "new-treasury-address-is-zero");
        require(address(vusd) == ITreasury(_newTreasury).vusd(), "vusd-mismatch");
        uint256 _len = _cometList.length();
        for (uint256 i = 0; i < _len; i++) {
            address _comet = _cometList.at(i);
            IERC20(_comet).safeTransfer(_newTreasury, IERC20(_comet).balanceOf(address(this)));
        }
    }

    /**
     * @notice Withdraw given amount of token.
     * @dev Only Redeemer and Governor are allowed to call
     * @param _token Token to withdraw, it should be 1 of the supported tokens.
     * @param _amount token amount to withdraw
     */
    function withdraw(address _token, uint256 _amount) external nonReentrant onlyAuthorized {
        _withdraw(_token, _amount, _msgSender());
    }

    /**
     * @notice Withdraw given amount of token.
     * @dev Only Redeemer and Governor are allowed to call
     * @param _token Token to withdraw, it should be 1 of the supported tokens.
     * @param _amount token amount to withdraw
     * @param _tokenReceiver Address of token receiver
     */
    function withdraw(address _token, uint256 _amount, address _tokenReceiver) external nonReentrant onlyAuthorized {
        _withdraw(_token, _amount, _tokenReceiver);
    }

    /**
     * @notice Withdraw multiple tokens.
     * @dev Only Governor is allowed to call.
     * @dev _tokens and _amounts array are 1:1 and should have same length
     * @param _tokens Array of token addresses, tokens should be supported tokens.
     * @param _amounts Array of token amount to withdraw
     */
    function withdrawMulti(address[] memory _tokens, uint256[] memory _amounts) external nonReentrant onlyGovernor {
        require(_tokens.length == _amounts.length, "input-length-mismatch");
        for (uint256 i = 0; i < _tokens.length; i++) {
            _withdraw(_tokens[i], _amounts[i], _msgSender());
        }
    }

    /**
     * @notice Withdraw all of multiple tokens.
     * @dev Only Governor is allowed to call.
     * @param _tokens Array of token addresses, tokens should be supported tokens.
     */
    function withdrawAll(address[] memory _tokens) external nonReentrant onlyGovernor {
        for (uint256 i = 0; i < _tokens.length; i++) {
            require(_whitelistedTokens.contains(_tokens[i]), "token-is-not-supported");
            IComet(comets[_tokens[i]]).withdrawTo(_msgSender(), _tokens[i], type(uint256).max);
        }
    }

    /**
     * @notice Sweep any ERC20 token to governor address
     * @dev OnlyGovernor can call this and comets are not allowed to sweep
     * @param _fromToken Token address to sweep
     */
    function sweep(address _fromToken) external onlyGovernor {
        // Do not sweep comets
        require(!_cometList.contains(_fromToken), "comet-is-not-allowed-to-sweep");

        uint256 _amount = IERC20(_fromToken).balanceOf(address(this));
        IERC20(_fromToken).safeTransfer(_msgSender(), _amount);
    }

    /**
     * @notice Current withdrawable amount for given token.
     * If token is not supported by treasury, no comets in mapping, it will return 0.
     * @param _token Token to withdraw
     */
    function withdrawable(address _token) external view returns (uint256) {
        if (comets[_token] != address(0)) {
            return IComet(comets[_token]).balanceOf(address(this));
        }
        return 0;
    }

    /// @dev Governor is defined in VUSD token contract only
    function governor() public view returns (address) {
        return vusd.governor();
    }

    /// @notice Return list of comets
    function cometList() external view returns (address[] memory) {
        return _cometList.values();
    }

    /// @notice Return list of keepers
    function keepers() external view returns (address[] memory) {
        return _keepers.values();
    }

    /// @notice Returns whether given address is whitelisted or not
    function isWhitelistedToken(address _address) external view returns (bool) {
        return _whitelistedTokens.contains(_address);
    }

    /// @notice Return list of whitelisted tokens
    function whitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokens.values();
    }

    /// @dev Add _token into the list, add _comet in mapping
    function _addToken(address _token, address _comet, address _oracle) internal {
        require(IComet(_comet).baseToken() == _token, "invalid-token");
        require(_whitelistedTokens.add(_token), "add-in-list-failed");
        require(_cometList.add(_comet), "add-in-list-failed");
        oracles[_token] = _oracle;
        comets[_token] = _comet;
        IERC20(_token).safeApprove(_comet, type(uint256).max);
    }

    function _withdraw(address _token, uint256 _amount, address _tokenReceiver) internal {
        require(_whitelistedTokens.contains(_token), "token-is-not-supported");
        IComet(comets[_token]).withdrawTo(_tokenReceiver, _token, _amount);
    }
}
