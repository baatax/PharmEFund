// SPDX-License-Identifier: MIT
/*
Testing results:
15 >50% voted contracts -> End vote was 573807 gas
Tested Milestones -> Everything works accordingly
Contract deployment is 4867951 Gas
Fund with 0.6 exponent and 2x softcap funding: 216623 gas



*/


//Make it accept stable coins
//Make variable milestone rewards possible
//Change minutes to days for final deployment
/*
13-04-22 Axel de Baat

*/
pragma solidity ^0.8.2;

interface Token {
    function transfer(address, uint256) external returns(bool);
    function increaseAllowance(address,uint256) external returns(bool);
    function transferFrom(address,address,uint256) external returns(bool);
}


contract Funding_Round{
   
    event Proposal_made(address indexed Proposer_address, uint256 indexed Proposal_id,uint256); //Proposer, ID, Costs, Milestones
    event Funding_Added(address indexed Funder_address,uint256, uint256); // Funder, Time, amount, new voting power
    event Vote_cast(address indexed Voter_address, uint256 indexed Proposal_id, uint256);
    event Milestone_Unlocked(uint256 indexed Proposal_id, uint256 Milestone_Nr); //Proposal Id, Milestone Nr
    event Refunding(address Refunder, uint256 Amount); //Refunder and amount
    event Vote_Ended(uint64 Vote_Ending); // UNIX Time where vote ended

    struct Proposal {
        bool funded;        //funding assigned by end_vote function
        bool liquidated;    //Modified by liquidate_proposal
        uint256[] milestones;   //Specified by user
        address proposer;   //Address of user - address funding will be sent to
        uint256 requested;  //Amount of funding needed to implement proposal
        uint256 paid_out;   //How much funding has already been paid out
        mapping(uint256 => uint256) msvotes;    //Votes per milestone to release funds (gets reset each milestone)
        uint256 votes;      //Votes in favor of funding proposal
        bool[] mspayout;    //List that tracks each milestone paid out by adding another entry
        mapping(uint256 => mapping (address => bool)) has_voted; // Tracks which funders have already voted
        mapping(address => uint256) voters; // Tracks voting power of funders
    }
    mapping(uint256 => Proposal) proposals; //Datastructure containing all proposals
    mapping(address => uint256) votingPower;//Actual voting power per address
    mapping(address => uint256) totalFunded;//Funding in the pool supplied by specific address
    uint256[] _remainingProps;              //List of half-funded projects populated by end_vote
    uint256[] public prop_ids;                     //List of all the proposal_ids, used by End_vote to iterate over
    address public _token;
    uint64 public _voteduration;
    uint64 public _propduration;
    uint64 public vote_end;
    uint64 public prop_end;
    uint64 public vote_ended;
    uint64 public liq_time;

    uint256 public _remainingFunds;         //Funds remaining in the pool
    uint256 public _fundSoftcap;            //Soft cap after which voting will become radical 
    uint256 public _remainingVotes;         //Total votes that have not been cast
    uint256 public danger_zone;             //Point after which funding function stops returning voting(funds) > funds
    uint256 public _mult;                   //Multiplication factor for funding = (_fundSoftcap)**0.3
    uint8 public _exp;                      //Numerator for exponent of root function (base 10)
    
    

    constructor(address token_,uint64 vote_mins, uint256 fundsoftcap_, uint256 dangerzone_, uint64 prop_mins, uint64 liqtime_mins, uint8 exp_) {
        _voteduration = vote_mins *60;                      //Duration of voting phase
        _propduration = prop_mins *60;                      //Duration of proposal phase
        _fundSoftcap = fundsoftcap_;                        //Funding Soft Cap
        prop_end = toUint64(block.timestamp) + _propduration;  // Block nr where proposal phase ends
        vote_end =  prop_end + _voteduration;               // Block nr where voting phase ends
        liq_time = liqtime_mins *60;                                // Blocks after milestones expire that funders can liquidate remaining funds
        _exp = exp_;                                        // Exponent of root function (base 10)
        _mult = determineMult();                             // Multiplication in: votingpower(fund) = (fund**exp/10) * _mult
        danger_zone = dangerzone_;                          // Dangerzone over softcap where VP function returns >1 vote per unit funded
        _token = token_;                                    //Assign address of Pharmatoken
    }

    //Calculates multiplication factor for voting power function by: (_fundSoftcap)**0.3
    function determineMult() internal view returns(uint256){ 
        (uint256 pwr,uint8 prec) = power(_fundSoftcap, 1, 3, 10); // Function returns Large number/ 2**Precision as output
        return pwr/(2**prec);
    }
    function getVotingpower(address voter)public view returns(uint256){
        return votingPower[voter];
    }
    function getAmountfunded(address funder)public view returns(uint256){
        return totalFunded[funder];
    }
    function getFundingstatus(uint256 id) public view returns(bool){
        return proposals[id].funded;
    }
    function getFundingrequested(uint256 id) public view returns(uint256){
        return proposals[id].requested;
    }
    function getPayouts(uint256 id) public view returns(uint256){
        return proposals[id].mspayout.length;
    }
    function getMilestones(uint256 id) public view returns(uint256){
        return proposals[id].milestones.length;
    }
    // Refund function that distributes remaining funds based on remaining unused voting power
    function Refund() public {
        require(vote_ended > 0, "Refund: Funding round has not ended yet");                 
        uint256 amt = _remainingFunds*(votingPower[msg.sender]*100000/_remainingVotes)/100000; //Calculates refund owed based on fraction of remaining voting power
        require(amt>0,"Refund: Nothing to refund");
        _remainingVotes -= votingPower[msg.sender];
        _remainingFunds -= amt;
        votingPower[msg.sender] = 0;
        Token(_token).transfer(msg.sender,amt);
        emit Refunding(msg.sender, amt);
    }
    //Function to return funds left in proposal if proposal duration is expired and funders no longer wish to give developers funds
    function LiquidateProposal(uint256 prop_id) public{ 
        Proposal storage prop = proposals[prop_id];
        require(prop.funded, "LiquidateProposal: Proposal not funded");
        require(vote_ended+liq_time > block.timestamp, "LiquidateProposal: Not yet able to return funds");
        require(prop.voters[msg.sender] > 0, "LiquidateProposal: Not a funder");
        prop.liquidated = true; // Prevent further unlocking of milestones
        uint256 refund = (prop.voters[msg.sender]*(prop.milestones.length-prop.mspayout.length)/prop.milestones.length);
        prop.voters[msg.sender] = 0; // subtract remaining voting power
        Token(_token).transfer(msg.sender,refund);


    }
    function Unlock_Milestone(uint256 prop_id) public{
        Proposal storage pr = proposals[prop_id];
        uint256 msnr = pr.mspayout.length;
        require(pr.liquidated == false,"Unlock_Milestone: Proposal liquidated");
        require(pr.mspayout.length < pr.milestones.length, "Unlock_Milestone: All milestones already paid out");
        require(pr.has_voted[msnr][msg.sender] == false, "Unlock_Milestone:You have already voted this milestone");
        require(pr.funded, "Unlock_Milestone: Proposal not funded");
        require(pr.voters[msg.sender] > 0, "Unlock_Milestone: Not a funder.");
        pr.msvotes[msnr] += pr.voters[msg.sender]; // Add voters votes to milestone total
        pr.has_voted[msnr][msg.sender] = true;  // Prevent double voting
        if(pr.msvotes[msnr] > (pr.votes/2)){ // Initiate transfer of funds after milestone quorum is reached
            pr.mspayout.push(true);     //Add milestone completed
            pr.paid_out += pr.milestones[msnr];     //Add payment to total paid out balance 
            emit Milestone_Unlocked(prop_id, pr.mspayout.length);
            require(Token(_token).transfer(pr.proposer,pr.milestones[msnr]), "Unlock_Milestone: Transfer Failed.");
        }
    }
    //Function that generates proposal struct and adds it to proposals list
    function Propose(string calldata _salt, uint256 _amountNeeded, uint256[] calldata milestones) public returns(uint256) {
        require(prop_end > block.timestamp, "Propose: Funding round ended");
        require(_sumMilestones(milestones) == _amountNeeded, "Propose: Funding required doesn't match milestones");
        uint256 _id =  uint256(keccak256(abi.encode(msg.sender, _salt))); //Create unique proposal id
        Proposal storage pr = proposals[_id];   //Create new Proposal struct mapped to proposal Id
        pr.proposer = msg.sender;               //Add several parameters based on input
        pr.requested = _amountNeeded;
        pr.milestones = milestones;
        
        
        emit Proposal_made(msg.sender, _id,_amountNeeded);
        prop_ids.push(_id);                     
        return _id;
    }

    //Funding function that converts funding to voting power
    //Dimishes funding above softcap through a sqrt function partially parameterized by constructor
    //Danger zone refers to area where sqrt function returns voting power> funding when multiplication is used in the function
    function Fund(uint256 amt) public payable{
        require(vote_end > block.timestamp, "Fund: Funding period is closed"); //Technically optional
        require(Token(_token).increaseAllowance(address(this),amt), "Fund: Allowance failed");
        require(Token(_token).transferFrom(msg.sender, address(this),amt), "Fund: Transfer Failed");
        uint256 total_funded = totalFunded[msg.sender] + amt;
        uint256 voting_power;
        
        if (total_funded > _fundSoftcap){ // Check if softcap is broken
            require (total_funded > (_fundSoftcap+danger_zone), "Fund: Funding in danger zone, fund more");
            uint256 pwr;
            uint8 prec;
            (pwr, prec) = power((total_funded - _fundSoftcap), 1, _exp, 10); // Function returns Large number/ 2**Precision as output
            uint256 quadratic = (pwr/2**prec)*_mult;  // Actual result is calculated
            voting_power = quadratic + _fundSoftcap;
        }
        else{   // When softcap is not broken
            voting_power = total_funded;
        }
        totalFunded[msg.sender] += amt;         //Add new funding to total funded for future softcap calculations
        uint256 diff = voting_power - votingPower[msg.sender];   //Calculate increase in voting power
        _remainingVotes += diff;                                //Add differential to total voting power (for future returns)
        votingPower[msg.sender] = voting_power;                 //Store new voting power balance
        _remainingFunds += amt;                 //Add new funds to total funds balance
        emit Funding_Added(msg.sender, amt, diff);
    }

    //Voting function that allows allocation of voting power gained by providing funds to proposals
    function Vote(uint256 prop_id, uint256 amt) public{
        require(vote_end > block.timestamp && prop_end < block.timestamp, "Vote: Currently no voting round");
        require(votingPower[msg.sender] >= amt, "Vote: Not enough voting power");
        require((proposals[prop_id].requested - proposals[prop_id].votes) >= amt, "Vote: Cannot overfund proposal, allocate less votes.");
        votingPower[msg.sender] -= amt;    
        proposals[prop_id].votes += amt;    //Add to total vote balance(needed for end_vote algorithm)
        proposals[prop_id].voters[msg.sender] += amt;   //Add voter specific balance (needed for milestone unlocking)
        _remainingVotes -= amt; // Subtract cast votes from total voting pool (for refund purposes)
        emit Vote_cast(msg.sender, prop_id, amt);
    }

    // Function that ends voting period and decides which proposals get funded while optimizing capital allocation
    // Function iterates over all proposals and checks if total funding is met, if so proposal is funded
    // If proposal manages to get over 50% of required funds in votes, it is added to _remainingProps
    // Function then iterates over all remaining proposals ordered by first submission checking if enough _remainingfunds are left to fully fund proposal
    // Function will stop once _remainingFunds are used up
    function EndVote() public{
        require(vote_end < block.timestamp, "Funding round has not ended yet");

        for (uint16 i = 0 ; i < prop_ids.length; i++) {
            
            Proposal storage proposal = proposals[prop_ids[i]];
            if (proposal.votes == proposal.requested){ //Fund if votes meet requested amount
                proposals[prop_ids[i]].funded = true;
                _remainingFunds -= proposal.requested;
            }
            else{
                if(proposal.requested <= _remainingFunds){ // check if enough funds are left
                    uint256 vote_ratio = (proposal.votes*1000000)/proposal.requested;
                    if( vote_ratio > 500000){ //Check if more than 50% of votes are received
                        _remainingProps.push(prop_ids[i]); // Add to remaining props list
                    }
                }
            }
        }
        if (_remainingProps.length > 0){ //If there are any fundable proposals left
            
            for(uint16 j=0; j< _remainingProps.length; j++){ //While there is still funding left
                if(proposals[_remainingProps[j]].funded == false){ //Check if not funded already
                    if(proposals[_remainingProps[j]].requested <= _remainingFunds){ //Check if there is enough funding left
                        _remainingFunds -= proposals[_remainingProps[j]].requested; // Subtract funding
                        proposals[_remainingProps[j]].funded = true;}   //Set funded as true
                    }
                
                }
            }
        
        vote_ended = uint64(block.timestamp); //Save endblock of vote
        emit Vote_Ended(vote_ended);
    }
    function _sumMilestones(uint256[] memory mstones)internal pure returns (uint256) {
        uint256 sum;
        for (uint8 i=0; i< mstones.length; i++){
            sum += mstones[i];
        }
        return sum; 
    }

    function toUint64(uint256 value) private pure returns (uint64) {
        require(value <= type(uint64).max, "value doesn't fit in 32 bits");
        return uint64(value);
    }
    // From: https://github.com/Muhammad-Altabba/solidity-toolbox/blob/master/contracts/FractionalExponents.sol
    //Power function to calculate fractional exponent powers for voting power function
    uint256 private constant ONE = 1;
    uint32 private constant MAX_WEIGHT = 1000000;
    uint8 private constant MIN_PRECISION = 32;
    uint8 private constant MAX_PRECISION = 127;

    uint256 private constant FIXED_1 = 0x080000000000000000000000000000000;
    uint256 private constant FIXED_2 = 0x100000000000000000000000000000000;
    uint256 private constant MAX_NUM = 0x200000000000000000000000000000000;

    uint256 private constant LN2_NUMERATOR   = 0x3f80fe03f80fe03f80fe03f80fe03f8;
    uint256 private constant LN2_DENOMINATOR = 0x5b9de1d10bf4103d647b0955897ba80;

    uint256 private constant OPT_LOG_MAX_VAL = 0x15bf0a8b1457695355fb8ac404e7a79e3;
    uint256 private constant OPT_EXP_MAX_VAL = 0x800000000000000000000000000000000;

    uint256[128] private maxExpArray;
    /**
        General Description:
            Determine a value of precision.
            Calculate an integer approximation of (_baseN / _baseD) ^ (_expN / _expD) * 2 ^ precision.
            Return the result along with the precision used.
        Detailed Description:
            Instead of calculating "base ^ exp", we calculate "e ^ (log(base) * exp)".
            The value of "log(base)" is represented with an integer slightly smaller than "log(base) * 2 ^ precision".
            The larger "precision" is, the more accurately this value represents the real value.
            However, the larger "precision" is, the more bits are required in order to store this value.
            And the exponentiation function, which takes "x" and calculates "e ^ x", is limited to a maximum exponent (maximum value of "x").
            This maximum exponent depends on the "precision" used, and it is given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
            Hence we need to determine the highest precision which can be used for the given input, before calling the exponentiation function.
            This allows us to compute "base ^ exp" with maximum accuracy and without exceeding 256 bits in any of the intermediate computations.
            This functions assumes that "_expN < 2 ^ 256 / log(MAX_NUM - 1)", otherwise the multiplication should be replaced with a "safeMul".
    */
    function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) public view returns (uint256, uint8) {
        assert(_baseN < MAX_NUM);

        uint256 baseLog;
        uint256 base = _baseN * FIXED_1 / _baseD;
        if (base < OPT_LOG_MAX_VAL) {
            baseLog = optimalLog(base);
        }
        else {
            baseLog = generalLog(base);
        }

        uint256 baseLogTimesExp = baseLog * _expN / _expD;
        if (baseLogTimesExp < OPT_EXP_MAX_VAL) {
            return (optimalExp(baseLogTimesExp), MAX_PRECISION);
        }
        else {
            uint8 precision = findPositionInMaxExpArray(baseLogTimesExp);
            return (generalExp(baseLogTimesExp >> (MAX_PRECISION - precision), precision), precision);
        }
    }

    /**
        Compute log(x / FIXED_1) * FIXED_1.
        This functions assumes that "x >= FIXED_1", because the output would be negative otherwise.
    */
    function generalLog(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        // If x >= 2, then we compute the integer part of log2(x), which is larger than 0.
        if (x >= FIXED_2) {
            uint8 count = floorLog2(x / FIXED_1);
            x >>= count; // now x < 2
            res = count * FIXED_1;
        }

        // If x > 1, then we compute the fraction part of log2(x), which is larger than 0.
        if (x > FIXED_1) {
            for (uint8 i = MAX_PRECISION; i > 0; --i) {
                x = (x * x) / FIXED_1; // now 1 < x < 4
                if (x >= FIXED_2) {
                    x >>= 1; // now 1 < x < 2
                    res += ONE << (i - 1);
                }
            }
        }

        return res * LN2_NUMERATOR / LN2_DENOMINATOR;
    }

    /**
        Compute the largest integer smaller than or equal to the binary logarithm of the input.
    */
    function floorLog2(uint256 _n) internal pure returns (uint8) {
        uint8 res = 0;

        if (_n < 256) {
            // At most 8 iterations
            while (_n > 1) {
                _n >>= 1;
                res += 1;
            }
        }
        else {
            // Exactly 8 iterations
            for (uint8 s = 128; s > 0; s >>= 1) {
                if (_n >= (ONE << s)) {
                    _n >>= s;
                    res |= s;
                }
            }
        }

        return res;
    }

    /**
        The global "maxExpArray" is sorted in descending order, and therefore the following statements are equivalent:
        - This function finds the position of [the smallest value in "maxExpArray" larger than or equal to "x"]
        - This function finds the highest position of [a value in "maxExpArray" larger than or equal to "x"]
    */
    function findPositionInMaxExpArray(uint256 _x) internal view returns (uint8) {
        uint8 lo = MIN_PRECISION;
        uint8 hi = MAX_PRECISION;

        while (lo + 1 < hi) {
            uint8 mid = (lo + hi) / 2;
            if (maxExpArray[mid] >= _x)
                lo = mid;
            else
                hi = mid;
        }

        if (maxExpArray[hi] >= _x)
            return hi;
        if (maxExpArray[lo] >= _x)
            return lo;

        assert(false);
        return 0;
    }

    /**
        This function can be auto-generated by the script 'PrintFunctionGeneralExp.py'.
        It approximates "e ^ x" via maclaurin summation: "(x^0)/0! + (x^1)/1! + ... + (x^n)/n!".
        It returns "e ^ (x / 2 ^ precision) * 2 ^ precision", that is, the result is upshifted for accuracy.
        The global "maxExpArray" maps each "precision" to "((maximumExponent + 1) << (MAX_PRECISION - precision)) - 1".
        The maximum permitted value for "x" is therefore given by "maxExpArray[precision] >> (MAX_PRECISION - precision)".
    */
    function generalExp(uint256 _x, uint8 _precision) internal pure returns (uint256) {
        uint256 xi = _x;
        uint256 res = 0;

        xi = (xi * _x) >> _precision; res += xi * 0x3442c4e6074a82f1797f72ac0000000; // add x^02 * (33! / 02!)
        xi = (xi * _x) >> _precision; res += xi * 0x116b96f757c380fb287fd0e40000000; // add x^03 * (33! / 03!)
        xi = (xi * _x) >> _precision; res += xi * 0x045ae5bdd5f0e03eca1ff4390000000; // add x^04 * (33! / 04!)
        xi = (xi * _x) >> _precision; res += xi * 0x00defabf91302cd95b9ffda50000000; // add x^05 * (33! / 05!)
        xi = (xi * _x) >> _precision; res += xi * 0x002529ca9832b22439efff9b8000000; // add x^06 * (33! / 06!)
        xi = (xi * _x) >> _precision; res += xi * 0x00054f1cf12bd04e516b6da88000000; // add x^07 * (33! / 07!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000a9e39e257a09ca2d6db51000000; // add x^08 * (33! / 08!)
        xi = (xi * _x) >> _precision; res += xi * 0x000012e066e7b839fa050c309000000; // add x^09 * (33! / 09!)
        xi = (xi * _x) >> _precision; res += xi * 0x000001e33d7d926c329a1ad1a800000; // add x^10 * (33! / 10!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000002bee513bdb4a6b19b5f800000; // add x^11 * (33! / 11!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000003a9316fa79b88eccf2a00000; // add x^12 * (33! / 12!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000048177ebe1fa812375200000; // add x^13 * (33! / 13!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000005263fe90242dcbacf00000; // add x^14 * (33! / 14!)
        xi = (xi * _x) >> _precision; res += xi * 0x000000000057e22099c030d94100000; // add x^15 * (33! / 15!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000057e22099c030d9410000; // add x^16 * (33! / 16!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000052b6b54569976310000; // add x^17 * (33! / 17!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000004985f67696bf748000; // add x^18 * (33! / 18!)
        xi = (xi * _x) >> _precision; res += xi * 0x000000000000003dea12ea99e498000; // add x^19 * (33! / 19!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000000031880f2214b6e000; // add x^20 * (33! / 20!)
        xi = (xi * _x) >> _precision; res += xi * 0x000000000000000025bcff56eb36000; // add x^21 * (33! / 21!)
        xi = (xi * _x) >> _precision; res += xi * 0x000000000000000001b722e10ab1000; // add x^22 * (33! / 22!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000001317c70077000; // add x^23 * (33! / 23!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000000000000cba84aafa00; // add x^24 * (33! / 24!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000000000000082573a0a00; // add x^25 * (33! / 25!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000000000000005035ad900; // add x^26 * (33! / 26!)
        xi = (xi * _x) >> _precision; res += xi * 0x000000000000000000000002f881b00; // add x^27 * (33! / 27!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000000000001b29340; // add x^28 * (33! / 28!)
        xi = (xi * _x) >> _precision; res += xi * 0x00000000000000000000000000efc40; // add x^29 * (33! / 29!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000000000000007fe0; // add x^30 * (33! / 30!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000000000000000420; // add x^31 * (33! / 31!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000000000000000021; // add x^32 * (33! / 32!)
        xi = (xi * _x) >> _precision; res += xi * 0x0000000000000000000000000000001; // add x^33 * (33! / 33!)

        return res / 0x688589cc0e9505e2f2fee5580000000 + _x + (ONE << _precision); // divide by 33! and then add x^1 / 1! + x^0 / 0!
    }

    /**
        Return log(x / FIXED_1) * FIXED_1
        Input range: FIXED_1 <= x <= LOG_EXP_MAX_VAL - 1
    */
    function optimalLog(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        uint256 y;
        uint256 z;
        uint256 w;

        if (x >= 0xd3094c70f034de4b96ff7d5b6f99fcd8) {res += 0x40000000000000000000000000000000; x = x * FIXED_1 / 0xd3094c70f034de4b96ff7d5b6f99fcd8;}
        if (x >= 0xa45af1e1f40c333b3de1db4dd55f29a7) {res += 0x20000000000000000000000000000000; x = x * FIXED_1 / 0xa45af1e1f40c333b3de1db4dd55f29a7;}
        if (x >= 0x910b022db7ae67ce76b441c27035c6a1) {res += 0x10000000000000000000000000000000; x = x * FIXED_1 / 0x910b022db7ae67ce76b441c27035c6a1;}
        if (x >= 0x88415abbe9a76bead8d00cf112e4d4a8) {res += 0x08000000000000000000000000000000; x = x * FIXED_1 / 0x88415abbe9a76bead8d00cf112e4d4a8;}
        if (x >= 0x84102b00893f64c705e841d5d4064bd3) {res += 0x04000000000000000000000000000000; x = x * FIXED_1 / 0x84102b00893f64c705e841d5d4064bd3;}
        if (x >= 0x8204055aaef1c8bd5c3259f4822735a2) {res += 0x02000000000000000000000000000000; x = x * FIXED_1 / 0x8204055aaef1c8bd5c3259f4822735a2;}
        if (x >= 0x810100ab00222d861931c15e39b44e99) {res += 0x01000000000000000000000000000000; x = x * FIXED_1 / 0x810100ab00222d861931c15e39b44e99;}
        if (x >= 0x808040155aabbbe9451521693554f733) {res += 0x00800000000000000000000000000000; x = x * FIXED_1 / 0x808040155aabbbe9451521693554f733;}

        z = y = x - FIXED_1;
        w = y * y / FIXED_1;
        res += z * (0x100000000000000000000000000000000 - y) / 0x100000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa - y) / 0x200000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x099999999999999999999999999999999 - y) / 0x300000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x092492492492492492492492492492492 - y) / 0x400000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x08e38e38e38e38e38e38e38e38e38e38e - y) / 0x500000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x08ba2e8ba2e8ba2e8ba2e8ba2e8ba2e8b - y) / 0x600000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x089d89d89d89d89d89d89d89d89d89d89 - y) / 0x700000000000000000000000000000000; z = z * w / FIXED_1;
        res += z * (0x088888888888888888888888888888888 - y) / 0x800000000000000000000000000000000;

        return res;
    }

    /**
        Return e ^ (x / FIXED_1) * FIXED_1
        Input range: 0 <= x <= OPT_EXP_MAX_VAL - 1
    */
    function optimalExp(uint256 x) internal pure returns (uint256) {
        uint256 res = 0;

        uint256 y;
        uint256 z;

        z = y = x % 0x10000000000000000000000000000000;
        z = z * y / FIXED_1; res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = z * y / FIXED_1; res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = z * y / FIXED_1; res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = z * y / FIXED_1; res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = z * y / FIXED_1; res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = z * y / FIXED_1; res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = z * y / FIXED_1; res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = z * y / FIXED_1; res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = z * y / FIXED_1; res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = z * y / FIXED_1; res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = z * y / FIXED_1; res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = z * y / FIXED_1; res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = z * y / FIXED_1; res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = z * y / FIXED_1; res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = z * y / FIXED_1; res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = z * y / FIXED_1; res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = z * y / FIXED_1; res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = z * y / FIXED_1; res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = z * y / FIXED_1; res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        res = res / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

        if ((x & 0x010000000000000000000000000000000) != 0) res = res * 0x1c3d6a24ed82218787d624d3e5eba95f9 / 0x18ebef9eac820ae8682b9793ac6d1e776;
        if ((x & 0x020000000000000000000000000000000) != 0) res = res * 0x18ebef9eac820ae8682b9793ac6d1e778 / 0x1368b2fc6f9609fe7aceb46aa619baed4;
        if ((x & 0x040000000000000000000000000000000) != 0) res = res * 0x1368b2fc6f9609fe7aceb46aa619baed5 / 0x0bc5ab1b16779be3575bd8f0520a9f21f;
        if ((x & 0x080000000000000000000000000000000) != 0) res = res * 0x0bc5ab1b16779be3575bd8f0520a9f21e / 0x0454aaa8efe072e7f6ddbab84b40a55c9;
        if ((x & 0x100000000000000000000000000000000) != 0) res = res * 0x0454aaa8efe072e7f6ddbab84b40a55c5 / 0x00960aadc109e7a3bf4578099615711ea;
        if ((x & 0x200000000000000000000000000000000) != 0) res = res * 0x00960aadc109e7a3bf4578099615711d7 / 0x0002bf84208204f5977f9a8cf01fdce3d;
        if ((x & 0x400000000000000000000000000000000) != 0) res = res * 0x0002bf84208204f5977f9a8cf01fdc307 / 0x0000003c6ab775dd0b95b4cbee7e65d11;

        return res;
    }
}
