// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.2;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";
import "./ERC20.sol";
import "./Address.sol";
import "./IERC20.sol";


//wuky1998@gmail.com
contract MaticMoneyPro is ERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _AddressExists;
    mapping(address => uint256) private avaliableBnb;
    address[] private _addressList;
    address[] private _excluded;

    address private _devWallet;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 2000 * 10 ** 8 * 10 ** 9;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));

    uint256 private _tFeeTotal;

    uint256 public _taxFee = 1;
    uint256 public _liquidityFee = 1;
    uint256 public _lottoFee = 3;

    uint256 public _fomoFee = 3;
    uint256 public _preFomoFee;

    uint256 public _devFee = 2;
    uint256 public _burnFee = 1;

    uint256 public tradingEnabledTimestamp;

    struct FomoWinner {
        address user;
        uint amount;
        uint value;
        uint fomoAward;
        uint buyTime;
        uint openFomoTime;
    }

    struct LottoWinner {
        address winner;
        uint256 amount;
        uint openFomoTime;
    }

    struct TData {
        uint tTransferAmount;
        uint tLiquidity;
        uint tLotto;
        uint tDev;
        uint tFomo;
        uint tBurn;
        uint tFee;
    }

    struct Buy {
        address user; uint amount; uint value; bool isFomo; uint time;
    }

    address public firstPrizeWinner;
    address public secondPrizeWinner;
    address public thirdPrizeWinner;

    LottoWinner[] public lottoWinnerList;

    FomoWinner public lastFomoBuyUser;
    FomoWinner[] public fomoWinnerList;
    uint256 public fomoIntervalTime = 30 minutes;
    uint256 public _minLottoBalance = 30000000000000000000;
    uint256 public _minFoMouyBuyUsdt = 30000000000000000000;
    uint256 public _maxTxAmount = 2 * 10 ** 8 * 10 ** 9;
    uint256 public numTokensSellToAddToLiquidity = 2 * 10 ** 8 * 10 ** 9;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public dogeAddress;
    address public constant DEAD = 0x0000000000000000000000000000000000000000;
    address public usdt;
    address public liquidityWallet;

    bool swapping;

    bool public settleFomoEnabled = true;
    bool public swapAndLiquifyEnabled = true;
    bool public swapDogeEnabled = true;
    bool public swapLiquifyEnabled = true;
    bool public swapFomoEnabled = true;
    bool public haveLastFomoBuy;

    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event SwapDoge(uint256 tokenAmount, uint256 doge);
    event SwapFomo(uint tokenAmount, uint bnb);
    event NewBuy(address user, uint amount, uint value, bool isFomo, uint time);
    event SettleFomoAward(address winner, uint fomoAward);
    event SettleLottoAward(address winner, uint lottoAward);
    event DrawLottoWinner(address winner);
    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    modifier lockTheSwap {
        swapping = true;
        _;
        swapping = false;
    }

    constructor(address _dogeAddress, address _routerAddress, address _usdt, address _devAddress, uint _tradingEnabledTimestamp) public ERC20("MaticMoneyPro", "MMP", _tTotal) {

        dogeAddress = _dogeAddress;
        usdt = _usdt;
        _devWallet = _devAddress;
        liquidityWallet = owner();

        tradingEnabledTimestamp = _tradingEnabledTimestamp;

        _rOwned[_msgSender()] = _rTotal;
        addAddress(_msgSender());
        addAddress(_devAddress);
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_routerAddress);
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
        .createPair(address(this), _uniswapV2Router.WETH());
        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_routerAddress] = true;
        _isExcludedFromFee[_devAddress] = true;

        _approve(owner(), _routerAddress, MAX);
        _approve(address(this), _routerAddress, MAX);

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function getFomoLength() public view returns (uint256){
        return fomoWinnerList.length;
    }

    function getLottoLength() public view returns (uint256){
        return lottoWinnerList.length;
    }

    function minLottoBalance() public view returns (uint256) {
        return _minLottoBalance;
    }

    function currentLottoPool() public view returns (uint256) {
        return IERC20(dogeAddress).balanceOf(address(this));
    }

    function currentFomoPool() public view returns (uint256){
        return avaliableBnb[address(this)];
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function isIncludeFromLotto(address account) public view returns (bool) {
        return _AddressExists[account];
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function settleFomo() public {
        _settleFomo(msg.sender, 0, false);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns (uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        uint256 rate = _getRate();
        if (!deductTransferFee) {
            return tAmount.mul(rate);
        } else {
            uint256 tTransferAmount = _getTValues(tAmount).tTransferAmount;
            return tTransferAmount.mul(rate);
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    //judge sell amount of usdt
    function canJoinFomoWin(uint256 amount, uint tokenValue) public view returns (bool can, uint value){
        can = false;
        value = 0;
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = usdt;
        uint[] memory amounts = uniswapV2Router.getAmountsOut(amount, path);
        if (amounts.length > 0) {
            value = amounts[amounts.length - 1];
            can = value >= tokenValue;
        }
    }

    function changeTradingEnabledTimestamp(uint tradeTime) public onlyOwner {
        require(tradeTime < tradingEnabledTimestamp, "can not change time!");
        tradingEnabledTimestamp = tradeTime;
    }

    function updateLiquidityWallet(address newLiquidityWallet) public onlyOwner {
        require(newLiquidityWallet != liquidityWallet, "The liquidity wallet is already this address");
        _isExcludedFromFee[newLiquidityWallet] = true;
        emit LiquidityWalletUpdated(newLiquidityWallet, liquidityWallet);
        liquidityWallet = newLiquidityWallet;
    }

    function settleLotto() public onlyOwner {
        require(firstPrizeWinner != address(0) &&
        secondPrizeWinner != address(0) &&
            thirdPrizeWinner != address(0), "invalid lotto winner address"
        );

        //swap doge
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance > 0) swapDogeAndLiquify(contractTokenBalance);
        uint lottoBalance = currentLottoPool();
        require(lottoBalance > 0, "dont have enough Doge!");
        uint reward;

        uint lotoken = calculateAnyFee(lottoBalance, 50);
        IERC20(dogeAddress).transfer(firstPrizeWinner, lotoken);
        reward = reward + lotoken;
        lottoWinnerList.push(LottoWinner(firstPrizeWinner, lotoken, block.timestamp));
        emit SettleLottoAward(firstPrizeWinner, lotoken);

        lotoken = calculateAnyFee(lottoBalance, 30);
        IERC20(dogeAddress).transfer(secondPrizeWinner, lotoken);
        reward = reward + lotoken;
        lottoWinnerList.push(LottoWinner(secondPrizeWinner, lotoken, block.timestamp));
        emit SettleLottoAward(secondPrizeWinner, lotoken);

        lotoken = lottoBalance.sub(reward);
        IERC20(dogeAddress).transfer(thirdPrizeWinner, lotoken);
        lottoWinnerList.push(LottoWinner(thirdPrizeWinner, lotoken, block.timestamp));
        emit SettleLottoAward(thirdPrizeWinner, lotoken);


        delete firstPrizeWinner;
        delete secondPrizeWinner;
        delete thirdPrizeWinner;

    }

    function random(uint randomDivisor) private view returns (uint256) {
        return  uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, randomDivisor)));
    }

    //random the lucky boy
    function drawLottoWinners() public onlyOwner {
        (address _firstPrizeWinner,uint256 randomNumber1) = drawAddress(block.number,1);
        firstPrizeWinner = _firstPrizeWinner;
        (address _secondPrizeWinner,uint256 randomNumber2) = drawAddress(randomNumber1,2);
        secondPrizeWinner = _secondPrizeWinner;
        (address _thirdPrizeWinner,) = drawAddress(randomNumber2,3);
        thirdPrizeWinner = _thirdPrizeWinner;
        emit DrawLottoWinner(firstPrizeWinner);
        emit DrawLottoWinner(secondPrizeWinner);
        emit DrawLottoWinner(thirdPrizeWinner);
    }

    function drawAddress(uint randomDivisor,uint256 _index) private returns (address,uint256){
        uint256 _random =  random(randomDivisor);
        uint256 randomNumber = _random.mod(_addressList.length);
        address winner = _addressList[randomNumber];
        (bool can,) = canJoinFomoWin(balanceOf(winner), _minLottoBalance);

        bool again = !(can &&
        !winner.isContract() &&
        winner != address(this) &&
        winner != uniswapV2Pair &&
        winner != address(uniswapV2Router));

        if (_index == 2 && winner == firstPrizeWinner) {
            again = true;
        }
        if (_index == 3 && (winner == secondPrizeWinner || winner == firstPrizeWinner)) {
            again = true;
        }

        if (again) {
            (address _w,) = drawAddress(randomDivisor,_index);
            winner = _w;
        }

        return (winner,_random);

    }


    function excludeFromReward(address account) external onlyOwner() {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function setUniswapRouter(address r) external onlyOwner {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(r);
        uniswapV2Router = _uniswapV2Router;
    }

    function setUniswapPair(address p) external onlyOwner {
        uniswapV2Pair = p;
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setTaxFee(uint256 taxFee) external onlyOwner() {
        _taxFee = taxFee;
    }

    function setLottoFee(uint256 lottoFee) external onlyOwner() {
        _lottoFee = lottoFee;
    }

    function setDevFee(uint256 devFee) external onlyOwner() {
        _devFee = devFee;
    }

    function setBurnFee(uint burnFee) external onlyOwner() {
        _burnFee = burnFee;
    }

    function setLiquidityFee(uint fee) external onlyOwner() {
        _liquidityFee = fee;
    }

    function setFomoFee(uint fee) external onlyOwner() {
        _fomoFee = fee;
    }

    function setDevAddress(address payable dev) external onlyOwner() {
        _devWallet = dev;
    }

    function setFoMouyBuyUsdt(uint256 minBalance) external onlyOwner() {
        _minFoMouyBuyUsdt = minBalance;
    }

    function setMinLottoBalance(uint256 minBalance) external onlyOwner() {
        _minLottoBalance = minBalance;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
        _liquidityFee = liquidityFee;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10 ** 2
        );
    }

    function setFomoIntervalTime(uint256 _seconds) external onlyOwner {
        fomoIntervalTime = _seconds;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function setSwapDogeEnabled(bool _enabled) external onlyOwner {
        swapDogeEnabled = _enabled;
    }

    function setSwapLiquifyEnabled(bool _enabled) external onlyOwner {
        swapLiquifyEnabled = _enabled;
    }

    function setNumTokensSellToAddToLiquidity(uint256 amount) external onlyOwner {
        numTokensSellToAddToLiquidity = amount;
    }

    function setSwapFomoEnabled(bool e) external onlyOwner {
        swapFomoEnabled = e;
    }

    function setSettleFomoEnabled(bool e) external onlyOwner {
        settleFomoEnabled = e;
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function addAddress(address adr) private {
        if (_AddressExists[adr])
            return;
        _AddressExists[adr] = true;
        _addressList.push(adr);
    }

    function _takeDev(uint256 tDev) private {
        uint256 currentRate = _getRate();
        uint256 rDev = tDev.mul(currentRate);

        _rOwned[_devWallet] = _rOwned[_devWallet].add(rDev);
        if (_isExcluded[_devWallet])
            _tOwned[_devWallet] = _tOwned[_devWallet].add(tDev);
    }


    function calculateAnyFee(uint256 _amount, uint256 _fee) private pure returns (uint256){
        return _amount.mul(_fee).div(
            10 ** 2
        );
    }


    function getTradingIsEnabled() public view returns (bool) {
        return block.timestamp >= tradingEnabledTimestamp;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {

        bool tradingIsEnabled = getTradingIsEnabled();

        // add liqiud
        if (!tradingIsEnabled) {
            require(_isExcludedFromFee[from] || _isExcludedFromFee[to], "This account cannot send tokens until trading is enabled");
        }

        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (
            owner() != from && to != owner() && to == uniswapV2Pair //add liquidity
        ) {
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
        }

        address _this = address(this);

        addAddress(from);
        addAddress(to);

        uint256 contractTokenBalance = balanceOf(_this);
        if (contractTokenBalance >= _maxTxAmount)
        {
            contractTokenBalance = _maxTxAmount;
        }
        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            swapAndLiquifyEnabled &&
            overMinTokenBalance &&
            !swapping &&
            from != uniswapV2Pair &&
            from != address(uniswapV2Router) &&
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            swapDogeAndLiquify(contractTokenBalance);
        }
        //indicates if fee should be deducted from transfer
        bool takeFee = !swapping;
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        address _router = address(uniswapV2Router);
        bool isSell = from != _router && to == uniswapV2Pair;


        uint _innerTransferAmount = amount;
        uint _innerTFee;

        if (takeFee) {
            bool swapFomo = isSell && swapFomoEnabled;

            if (!swapFomo) removeFomoFee();

            TData memory data = _getTValues(amount);
            _innerTransferAmount = data.tTransferAmount;
            uint tLiquidity = data.tLiquidity;
            uint tLotto = data.tLotto;
            uint tDev = data.tDev;
            uint tFomo = data.tFomo;
            uint tBurn = data.tBurn;
            uint tFee = data.tFee;

            _takeLiquidityAndLottoAndFomo(tLiquidity, tLotto, tFomo);
            _takeDev(tDev);
            if (tFomo > 0 && !swapping) {
                // sell action
                swapForFomo(tFomo);
            }
            _takeBurn(tBurn);

            _innerTFee = tFee;

            if (!swapFomo) restoreFomoFee();
        }

        _tokenTransfer(from, to, _innerTransferAmount);

        //reflect token
        if (_innerTFee > 0) _reflectFee(_innerTFee, _innerTFee.mul(_getRate()));

        if (settleFomoEnabled && !swapping) {
            //only buy
            bool isBuy = from == uniswapV2Pair && to != _router;
            _settleFomo(to, amount, isBuy);
        }
    }

    //swap doge to lotto pool
    function swapDogeAndLiquify(uint contractTokenBalance) private lockTheSwap {
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        //swap doge and add liquify
        uint256 _totalFees = _liquidityFee.add(_lottoFee);
        uint256 swapTokens = contractTokenBalance.mul(_liquidityFee).div(_totalFees);
        if (swapLiquifyEnabled) swapAndLiquify(swapTokens);

        uint256 sellTokens = balanceOf(address(this));
        if (swapDogeEnabled) swapTokensForDoge(sellTokens);
    }

    function removeFomoFee() private {
        if (_fomoFee == 0) return;
        _preFomoFee = _fomoFee;
        _fomoFee = 0;
    }

    function restoreFomoFee() private {
        _fomoFee = _preFomoFee;
    }

    //swap bnb to fomo pool
    function swapForFomo(uint256 token) private lockTheSwap {
        address _this = address(this);
        uint256 initialBalance = _this.balance;
        swapTokensForEth(token);
        uint256 newBalance = _this.balance.sub(initialBalance);
        avaliableBnb[_this] = avaliableBnb[_this].add(newBalance);
        emit SwapFomo(token, newBalance);
    }

    function _takeLiquidityAndLottoAndFomo(uint256 tLiquidity, uint256 tLotto, uint256 tFomo) private {
        uint256 tAmount = tLiquidity.add(tLotto).add(tFomo);
        uint256 rAmount = _getCurrentRateValue(tAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rAmount);
        if (_isExcluded[address(this)]) _tOwned[address(this)] = _tOwned[address(this)].add(tAmount);
    }

    function _takeBurn(uint256 tBurn) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        address _d = DEAD;
        _rOwned[_d] = _rOwned[_d].add(rBurn);
        if (_isExcluded[_d])
            _tOwned[_d] = _tOwned[_d].add(tBurn);
    }

    function _getCurrentRateValue(uint256 amount) private view returns (uint256 r){
        r = amount.mul(_getRate());
    }

    function _getTValues(uint256 tAmount) private view returns (TData memory) {
        uint tFee = calculateAnyFee(tAmount, _taxFee);
        uint256 tLiquidity = calculateAnyFee(tAmount, _liquidityFee);
        uint256 tLotto = calculateAnyFee(tAmount, _lottoFee);
        uint256 tDev = calculateAnyFee(tAmount, _devFee);
        uint256 tFomo = calculateAnyFee(tAmount, _fomoFee);
        uint256 tBurn = calculateAnyFee(tAmount, _burnFee);

        uint256 _t = tFee.add(tLiquidity).add(tLotto);
        _t = _t.add(tDev).add(tFomo).add(tBurn);
        uint tTransferAmount = tAmount.sub(_t);
        return TData(tTransferAmount, tLiquidity, tLotto, tDev, tFomo, tBurn, tFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);
        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;
        // swap tokens for ETH
        swapTokensForEth(half);
        // <- this breaks the ETH -> HATE swap when swap+liquify is triggered
        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);
        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForDoge(uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = dogeAddress;
        uint256 initialBalance = currentLottoPool();
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        emit SwapDoge(tokenAmount, currentLottoPool().sub(initialBalance));
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // add the liquidity
        uniswapV2Router.addLiquidityETH{value : ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    //settle fomo award
    function _settleFomo(address to, uint256 amount, bool isBuy) private {
        uint256 fomoPoolBalance = currentFomoPool();
        //only add fomobuy when buy action and  the pool balance is not zero and buy the min usdt
        bool canAddWaiting;
        uint _value;
        uint _now = block.timestamp;
        if (isBuy) {
            (bool can, uint value) = canJoinFomoWin(amount, _minFoMouyBuyUsdt);
            _value = value;
            if (can && fomoPoolBalance > 0 && !to.isContract()) {
                canAddWaiting = true;
            }
            emit NewBuy(to, amount, _value, canAddWaiting, _now);
        }

        uint fomoTime = _now + fomoIntervalTime;

        if (haveLastFomoBuy && _now > lastFomoBuyUser.openFomoTime) {
            //maybe is sell
            haveLastFomoBuy = false;

            address winner = lastFomoBuyUser.user;
            uint buyAmount = lastFomoBuyUser.amount;
            uint buyValue = lastFomoBuyUser.value;
            uint fomoAward = lastFomoBuyUser.fomoAward;
            uint buyTime = lastFomoBuyUser.buyTime;
            uint openFomoTime = lastFomoBuyUser.openFomoTime;

            delete lastFomoBuyUser;
            avaliableBnb[address(this)] = fomoPoolBalance.sub((fomoAward));
            //win record
            fomoWinnerList.push(FomoWinner(winner, buyAmount, buyValue, fomoAward, buyTime, openFomoTime));
            payable(winner).transfer(fomoAward);
            emit SettleFomoAward(winner, fomoAward);
        }
        // the last fomo buy user
        if (canAddWaiting) {
            haveLastFomoBuy = true;
            lastFomoBuyUser = FomoWinner(to, amount, _value, calculateAnyFee(currentFomoPool(), 40), _now, fomoTime);
        }
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount) private {
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 rAmount = tAmount.mul(_getRate());
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        emit Transfer(sender, recipient, tAmount);
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        uint256 rAmount = tAmount.mul(_getRate());
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        emit Transfer(sender, recipient, tAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 rAmount = tAmount.mul(_getRate());
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        emit Transfer(sender, recipient, tAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 rAmount = tAmount.mul(_getRate());
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        emit Transfer(sender, recipient, tAmount);
    }

}
