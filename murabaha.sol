// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
/*
Basic dept contract allows to borrow DAI for a fixed period of time using ETH as a colleteral
Fee is constant and predefined. In case of lack of payment the whole colleteral
will be liquidated and transfered to the lender.
*/
import 'VALORO.sol';

contract Murabaha {
//structure defining the basic terms of the loan
    struct Terms {
        //The amount of VALORO to be loaned
        uint256 loanVALAmount;
        //The amount of VALORO to be repayed on top of the loan amount as a fee
        uint256 feeVALAmount;
        //The amount of the colleteral in Rose. should be more valuable than
        //the loanVALOROAmount + feeVALOROAmount at any time during the loan
        uint256 ColleteralAmount;
        //the agreed amount to be repayed to the lender
        uint256 VALInstallment;
        //The time stamp by which the loan should be repayed. After it - the lender can  liquidate the colleteral
        uint256 repayByTimeStamp;
    }
    Terms public terms;

    struct Users{
        address lender;
        address borrower;
        address seller;
    }
    Users public users;

    struct RepayInstallment {
        uint256 paid;
        uint256 left; 
    }
    RepayInstallment public repayInstallment;
    

    //The loan can be in 11 states. Created, ApprovedLoan, Granted, ConfirmSell, ApprovedPur, Release, Purchased, Taken, Inactive
    //Here we define only two because in the latter the contract will be destroyed.
    enum State { Created, ApprovedLoan, Granted, ConfirmSell, ApprovedPur, Release, Purchased, Taken, Paid, Liquidated, Inactive }
    State public state;

    ///Only buyer/lender can call this function
    error OnlyLender();

    ///Only Seller can call this function
    error OnlySeller();

    ///Only Borrower can call this function
    error OnlyBorrower();

    //Modifier that prevents some functions to be callen in any other state than the provided one.
    modifier onlyInState(State expectedState) {
        require(state == expectedState, "Not allowed in this state");
        _;
    }
    modifier onlyLender(){
        if (msg.sender != lender) {
            revert OnlyLender();
        }
        _;
    }

    modifier onlySeller(){
        if (msg.sender != seller) {
            revert OnlySeller();
        }
        _;
    }

    modifier onlyBorrower(){
        if (msg.sender != borrower) {
            revert OnlyBorrower();
        }
        _;
    }

    
    uint256 public loanAmount;
    uint256 public colleteral;
    uint256 public feeAmount;
    uint256 public Installment;
    uint256 public price;
    uint256 public insurance;
    uint256 public time;
    uint256 public contractID;
    address payable public lender;
    address payable public borrower;
    address payable public seller;
    address public valAddress;
    address public contractAddress;

    constructor (address _valAddress){
        valAddress = _valAddress;
        state = State.Created;
        contractAddress = address(this);
        
    }

    //return contract state using contract id
    mapping(uint256 => State) public contractState;
    //return terms of the contract using addres of the lender
    mapping(address => Terms) public contractTerms;
    //return users using contract id
    mapping(uint256 => Users) public contractUsers;
    //return contract id using address
    mapping(address => uint256) public myID;
    //return installment details using contract ID
    mapping(uint256 => RepayInstallment) public contractInstallment;

    //done by the lender
    function fundLoan(address payable _borrower , address payable _lender, address payable _seller, 
    uint256 _loanVALAmount, uint256 _feeVALAmount, uint256 _ColleteralAmount,uint256 _VALInstallment ,uint256 _repayByTimeStamp) 
    public onlyInState(State.Created){
        contractID ++;
        borrower = _borrower;
        users.borrower = borrower;
        lender = _lender;
        users.lender = lender;
        seller = _seller;
        users.seller = seller;
        terms.loanVALAmount = _loanVALAmount *10 ** 18;
        loanAmount = terms.loanVALAmount;
        terms.feeVALAmount = _feeVALAmount*10 ** 18;
        feeAmount = terms.feeVALAmount;
        terms.ColleteralAmount = _ColleteralAmount*10 ** 18;
        colleteral = terms.ColleteralAmount;
        terms.VALInstallment= _VALInstallment*10 ** 18;
        Installment = terms.VALInstallment;
        //converting the time from millisecond to seconds
        terms.repayByTimeStamp= _repayByTimeStamp*10 ** 3;
        time = terms.repayByTimeStamp;
        require(terms.ColleteralAmount >= terms.loanVALAmount+terms.feeVALAmount, "please enter higher colleteral amount");
        contractTerms[lender]=Terms(terms.loanVALAmount, terms.feeVALAmount, terms.ColleteralAmount, terms.VALInstallment, terms.repayByTimeStamp);
        contractUsers[contractID]=Users(users.lender, users.borrower, users.seller);
        contractInstallment[contractID]= RepayInstallment(repayInstallment.paid, repayInstallment.left);
        myID[lender] = contractID;
        state = State.ApprovedLoan;
        contractState[contractID]= state;
    }

    //Function to take the colleteral from the borrower
    //address for this function should be borrower
    //colleteral should be transfered when calling this function
    function payColleteral() public payable onlyBorrower onlyInState(State.ApprovedLoan){
        //Check that the exact amount  of the colleteral  is transfered. it will kept in the contract till the loan  is repayed or liquidated
        require(msg.value == colleteral, "Invalid colleteral amount");
        //Record the borrower address so that only he/she can repay  the loan and unlock the colleteral
        VALORO(valAddress).increaseAllowance(borrower, contractAddress, 10**19);
        VALORO(valAddress).increaseAllowance(borrower, borrower, 10**19);
        state = State.Granted; 
        contractState[contractID]= state;
    }

    //below 5 functions are related to the purchase process between lender and seller 

    function confirmSeller() public onlySeller onlyInState(State.Granted){
        state = State.ConfirmSell;
        price = loanAmount;
        insurance = price;
        contractState[contractID]= state;
    }

    //insurance will be in Rose
    function confirmPurchase() public onlyLender onlyInState(State.ConfirmSell) payable {
        state = State.ApprovedPur;
        require(msg.value == (insurance), "Please send in the insuarance");
        VALORO(valAddress).increaseAllowance(lender, contractAddress, 10**19);
        VALORO(valAddress).increaseAllowance(lender, lender, 10**19); 
        contractState[contractID]= state;
    }

    function confirmRecievedLender() public onlyLender onlyInState(State.ApprovedPur) {
        state = State.Release;
        lender.transfer(insurance);
        contractState[contractID]= state;
    }

    function paySeller() public onlyLender onlyInState(State.Release){
        state = State.Purchased;
        VALORO(valAddress).transferFrom(
            lender,
            seller,
            price
        );
        contractState[contractID]= state;
    }

    function abort() external onlySeller onlyInState(State.Granted){
            state = State.Inactive;
            contractState[contractID]= state;
    }

    function confirmRecievedBorrower() public onlyBorrower onlyInState(State.Purchased) {
        state = State.Taken;
        contractState[contractID]= state;
    }

    
    function repay() public payable onlyBorrower onlyInState(State.Taken){
        require(msg.value == Installment, "plese enter the agrred monthly Installment");
        //Pull the tokens. Both the initial amount and the fee. If there is not enough it will fail.
        VALORO(valAddress).transferFrom(
            borrower,
            lender,
            Installment
        );
        repayInstallment.paid += Installment;
        repayInstallment.left = (loanAmount+ feeAmount) - repayInstallment.paid;
        contractInstallment[contractID]= RepayInstallment(repayInstallment.paid, repayInstallment.left);
        if (repayInstallment.left == 0){
            borrower.transfer(colleteral);
            state = State.Paid;
            contractState[contractID]= state;
        }
        
        
    }

    //This function to be called by the lender in case the loan is not repayed on time 
    //It will transfer the whole collateral to the lender. The colleteral is expected to be more valuable than the loan so that
    //the lender deosn't lose any money in this case.
    function liquidate() public onlyLender onlyInState(State.Taken) {
        require(block.timestamp >= time, "Can't liquidate  before the loan is due");
        lender.transfer(colleteral - repayInstallment.paid);
        state= State.Liquidated;
        contractState[contractID]= state;
    }

    // function newContract() public {
    //      state = State.Created;
    //      lender= payable(msg.sender);
    // }

}