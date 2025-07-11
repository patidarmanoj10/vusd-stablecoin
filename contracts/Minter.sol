// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAggregatorV3} from "./interfaces/chainlink/IAggregatorV3.sol";
import {IComet} from "./interfaces/compound/IComet.sol";
import {IVUSD} from "./interfaces/IVUSD.sol";

/// @title Minter contract which will mint VUSD 1:1, less minting fee, with USDC or USDT.
contract Minter is Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    string public constant NAME = "VUSD-Minter";
    string public constant VERSION = "1.5.0";

    IVUSD public immutable vusd;
    uint8 public immutable vusdDecimals;

    uint256 public mintingFee; // Default no fee
    uint256 public maxMintLimit; // Maximum VUSD can be minted

    uint256 public constant MAX_BPS = 10_000; // 10_000 = 100%
    uint256 public priceTolerance = 100; // 1% based on BPS

    // Token => comet mapping
    mapping(address => address) public comets;
    // Token => oracle mapping
    mapping(address => address) public oracles;

    // Oracle => stalePeriod mapping
    mapping(address => uint256) public stalePeriod;

    EnumerableSet.AddressSet private _whitelistedTokens;

    // Default whitelist token addresses
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    //solhint-disable const-name-snakecase
    // comet addresses for default whitelisted tokens
    address private constant cUSDCv3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address private constant cUSDTv3 = 0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840;

    // Chainlink price oracle for default whitelisted tokens
    address private constant USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private constant USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    event UpdatedMintingFee(uint256 previousMintingFee, uint256 newMintingFee);
    event UpdatedPriceTolerance(uint256 previousPriceTolerance, uint256 newPriceTolerance);
    event UpdatedStalePeriod(address indexed oracle, uint256 previousStalePeriod, uint256 newStalePeriod);
    event MintingLimitUpdated(uint256 previousMintLimit, uint256 newMintLimit);
    event Mint(
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountInAfterTransferFee,
        uint256 mintage,
        address receiver
    );
    event WhitelistedTokenAdded(address indexed token, address comet, address oracle);
    event WhitelistedTokenRemoved(address indexed token);

    constructor(address _vusd, uint256 _maxMintLimit) {
        require(_vusd != address(0), "vusd-address-is-zero");
        vusd = IVUSD(_vusd);
        maxMintLimit = _maxMintLimit;
        vusdDecimals = IERC20Metadata(_vusd).decimals();
        // Add token into the list, add oracle and comet into the mapping and approve comet to spend token
        _addToken(USDC, cUSDCv3, USDC_USD, 24 hours);
        _addToken(USDT, cUSDTv3, USDT_USD, 24 hours);
    }

    modifier onlyGovernor() {
        require(_msgSender() == governor(), "caller-is-not-the-governor");
        _;
    }

    ////////////////////////////// Only Governor //////////////////////////////
    /**
     * @notice Add token as whitelisted token for VUSD system
     * @dev Add token address in whitelistedTokens list and add comet in mapping
     * @param _token address which we want to add in token list.
     * @param _comet comet address correspond to _token
     * @param _oracle Chainlink oracle address for token/USD feed
     */
    function addWhitelistedToken(
        address _token,
        address _comet,
        address _oracle,
        uint256 _stalePeriod
    ) external onlyGovernor {
        require(_token != address(0), "token-address-is-zero");
        require(_comet != address(0), "comet-address-is-zero");
        require(_oracle != address(0), "oracle-address-is-zero");
        require(_stalePeriod > 0, "invalid-stale-period");
        _addToken(_token, _comet, _oracle, _stalePeriod);
    }

    /**
     * @notice Remove token from whitelisted tokens
     * @param _token address which we want to remove from token list.
     */
    function removeWhitelistedToken(address _token) external onlyGovernor {
        require(_whitelistedTokens.remove(_token), "remove-from-list-failed");
        IERC20(_token).safeApprove(comets[_token], 0);
        delete stalePeriod[oracles[_token]];
        delete comets[_token];
        delete oracles[_token];
        emit WhitelistedTokenRemoved(_token);
    }

    /**
     * @notice Mint request amount of VUSD and use minted VUSD to add liquidity
     * @param _amount Amount of VUSD to mint
     */
    function mint(uint256 _amount) external onlyGovernor {
        uint256 _availableMintage = availableMintage();
        require(_availableMintage >= _amount, "mint-limit-reached");
        vusd.mint(_msgSender(), _amount);
    }

    /// @notice Update minting fee
    function updateMintingFee(uint256 _newMintingFee) external onlyGovernor {
        require(_newMintingFee <= MAX_BPS, "minting-fee-limit-reached");
        require(mintingFee != _newMintingFee, "same-minting-fee");
        emit UpdatedMintingFee(mintingFee, _newMintingFee);
        mintingFee = _newMintingFee;
    }

    function updateMaxMintAmount(uint256 _newMintLimit) external onlyGovernor {
        uint256 _currentMintLimit = maxMintLimit;
        require(_currentMintLimit != _newMintLimit, "same-mint-limit");
        emit MintingLimitUpdated(_currentMintLimit, _newMintLimit);
        maxMintLimit = _newMintLimit;
    }

    /// @notice Update price deviation limit
    function updatePriceTolerance(uint256 _newPriceTolerance) external onlyGovernor {
        require(_newPriceTolerance <= MAX_BPS, "price-deviation-is-invalid");
        uint256 _currentPriceTolerance = priceTolerance;
        require(_currentPriceTolerance != _newPriceTolerance, "same-price-deviation-limit");
        emit UpdatedPriceTolerance(_currentPriceTolerance, _newPriceTolerance);
        priceTolerance = _newPriceTolerance;
    }

    /// @notice Update stale period
    function updateStalePeriod(address _oracle, uint256 _newStalePeriod) external onlyGovernor {
        require(_newStalePeriod != 0, "stale-period-is-invalid");
        uint256 _currentStalePeriod = stalePeriod[_oracle];
        require(_currentStalePeriod != 0, "invalid-oracle");
        require(_currentStalePeriod != _newStalePeriod, "same-stale-period");
        emit UpdatedStalePeriod(_oracle, _currentStalePeriod, _newStalePeriod);
        stalePeriod[_oracle] = _newStalePeriod;
    }

    ///////////////////////////////////////////////////////////////////////////

    /**
     * @notice Mint VUSD
     * @param _token Address of token being deposited
     * @param _amountIn Amount of _token
     * @param _minAmountOut Minimum amount of VUSD to mint
     * @param _receiver Address of VUSD receiver
     */
    function mint(address _token, uint256 _amountIn, uint256 _minAmountOut, address _receiver) external nonReentrant {
        _mint(_token, _amountIn, _minAmountOut, _receiver);
    }

    /**
     * @notice Calculate minting amount of VUSD for given _token and its amountIn.
     * @param _token Address of token which will be deposited for this mintage
     * @param _amountIn Amount of _token being sent to calculate VUSD mintage.
     * @return _mintage VUSD mintage based on given input
     * @dev _amountIn is amount received after transfer fee if there is any.
     */
    function calculateMintage(address _token, uint256 _amountIn) external view returns (uint256 _mintage) {
        if (_whitelistedTokens.contains(_token)) {
            _mintage = _calculateMintage(_token, _amountIn);
        }
    }

    /// @notice Returns whether given address is whitelisted or not
    function isWhitelistedToken(address _address) external view returns (bool) {
        return _whitelistedTokens.contains(_address);
    }

    /// @notice Return list of whitelisted tokens
    function whitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokens.values();
    }

    /// @notice Check available mintage based on mint limit
    function availableMintage() public view returns (uint256 _mintage) {
        uint256 _totalSupply = vusd.totalSupply();
        uint256 _mintageLimit = maxMintLimit;
        if (_mintageLimit > _totalSupply) {
            _mintage = _mintageLimit - _totalSupply;
        }
    }

    /// @dev Treasury is defined in VUSD token contract only
    function treasury() public view returns (address) {
        return vusd.treasury();
    }

    /// @dev Governor is defined in VUSD token contract only
    function governor() public view returns (address) {
        return vusd.governor();
    }

    /**
     * @dev Add _token into the list, add _comet in mapping and
     * approve comet to spend token
     */
    function _addToken(address _token, address _comet, address _oracle, uint256 _stalePeriod) internal {
        require(IComet(_comet).baseToken() == _token, "invalid-token");
        require(_whitelistedTokens.add(_token), "add-in-list-failed");
        oracles[_token] = _oracle;
        comets[_token] = _comet;
        stalePeriod[_oracle] = _stalePeriod;
        IERC20(_token).safeApprove(_comet, type(uint256).max);
        emit WhitelistedTokenAdded(_token, _comet, _oracle);
    }

    /**
     * @notice Mint VUSD
     * @param _token Address of token being deposited
     * @param _amountIn Amount of _token
     * @param _receiver Address of VUSD receiver
     */
    function _mint(
        address _token,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _receiver
    ) internal returns (uint256 _mintage) {
        require(_whitelistedTokens.contains(_token), "token-is-not-supported");
        uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(_msgSender(), address(this), _amountIn);
        uint256 _balanceAfter = IERC20(_token).balanceOf(address(this));

        uint256 _actualAmountIn = _balanceAfter - _balanceBefore;
        _mintage = _calculateMintage(_token, _actualAmountIn);
        require(_mintage >= _minAmountOut, "mint-amount-is-less-than-minimum");

        IComet(comets[_token]).supplyTo(treasury(), _token, _balanceAfter);

        vusd.mint(_receiver, _mintage);
        emit Mint(_token, _amountIn, _actualAmountIn, _mintage, _receiver);
    }

    /**
     * @notice Calculate mintage based on mintingFee, if any.
     * Also covert _token defined decimal amount to 18 decimal amount
     * @return _mintage VUSD mintage based on given input
     */
    function _calculateMintage(address _token, uint256 _amountIn) internal view returns (uint256 _mintage) {
        IAggregatorV3 _oracle = IAggregatorV3(oracles[_token]);
        uint8 _oracleDecimal = IAggregatorV3(_oracle).decimals();
        (, int256 _price, , uint256 _updatedAt, ) = IAggregatorV3(_oracle).latestRoundData();
        require(block.timestamp - _updatedAt < stalePeriod[address(_oracle)], "oracle-price-is-stale");
        uint256 _latestPrice = uint256(_price);

        // Token is expected to be stable coin only. Ideal price is 1 USD
        uint256 _oneUSD = 10 ** _oracleDecimal;
        uint256 _priceTolerance = (_oneUSD * priceTolerance) / MAX_BPS;
        uint256 _priceUpperBound = _oneUSD + _priceTolerance;
        uint256 _priceLowerBound = _oneUSD - _priceTolerance;

        require(_latestPrice <= _priceUpperBound && _latestPrice >= _priceLowerBound, "oracle-price-exceed-tolerance");
        uint256 _actualAmountIn = mintingFee > 0 ? (_amountIn * (MAX_BPS - mintingFee)) / MAX_BPS : _amountIn;
        _mintage = _latestPrice >= _oneUSD ? _actualAmountIn : (_actualAmountIn * _latestPrice) / _oneUSD;

        _mintage = _mintage * 10 ** (vusdDecimals - IERC20Metadata(_token).decimals());
        uint256 _availableMintage = availableMintage();
        require(_availableMintage >= _mintage, "mint-limit-reached");
    }
}
