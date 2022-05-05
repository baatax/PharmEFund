// SPDX-License-Identifier: MIT
//Axel de Baat

pragma solidity ^0.8.2;
interface Token {
    function transfer(address, uint256) external returns(bool);
    function increaseAllowance(address,uint256) external returns(bool);
    function transferFrom(address,address,uint256) external returns(bool);
}

contract Bounty_Board{
    address _token;

    constructor(address token_){
        _token = token_;
    }
    
    event Bounty_Posted(address indexed Poster, uint256 indexed Bounty_ID,uint256 Reward); 
    event Bounty_Funded(address indexed Funder, uint256 indexed Bounty_ID,uint256 Funding); 
    event Milestone_Unlocked(uint256 indexed Bounty_ID, uint256 Milestone_Nr); 
    event Bounty_Refunded(uint256 indexed Bounty_ID, address indexed Refunder, uint256 Amount); 


    struct Bounty {
            bool liquidated;                                        //Modified by liquidate_proposal
            uint64 start;
            uint64 duration;                                        //Specified by user
            uint256 reward;                                         //Amount of funding needed to implement proposal
            uint256 paid_out;                                       //How much funding has already been paid out
            uint256 funded;
            mapping(uint256 => uint256) msvotes;                    //Votes per milestone to release funds (gets reset each milestone)
            mapping(uint256 => bool) mspayout;                      //List that tracks each milestone paid out by adding another entry
            mapping(address => mapping(uint256 => bool)) has_voted; // Tracks which funders have already voted
            mapping(address => uint256) funders;                    // Tracks voting power of funders
            uint256[] msvalues;
        }
    mapping(uint256 => Bounty) bounties; //Datastructure containing all Bounties


    function Post_Bounty(string calldata _salt, uint64 days_duration, uint256 _reward, uint256[] calldata _msvalues, uint256 stake) public returns(uint256) {
        require(_reward == _sumMilestones(_msvalues), "Post_Bounty: msg.value does not correspond with milestone total");
        Token(_token).increaseAllowance(address(this),stake);
        Token(_token).transferFrom(msg.sender, address(this),stake);
        uint256 _id =  uint256(keccak256(abi.encode(msg.sender, _salt))); //Create unique proposal id
        Bounty storage bt = bounties[_id];   //Create new Proposal struct mapped to proposal Id
        bt.reward = _reward;
        bt.msvalues = _msvalues;
        bt.duration = days_duration *60*60*24;
        bt.start = toUint64(block.timestamp);
        bt.funded = stake;
        bt.funders[msg.sender] = stake;
        emit Bounty_Posted(msg.sender, _id,_reward);

        return _id;
        }
    
    function Fund_Bounty(uint256 _id, uint256 amt)public{
        Bounty storage bt = bounties[_id];
        require(bt.reward> bt.funded, "Fund_Bounty: Bounty already fully funded");
        require(amt > 0 && amt <= (bt.reward - bt.funded), "Fund_Bounty: No payment");
        Token(_token).increaseAllowance(address(this),amt);
        Token(_token).transferFrom(msg.sender,address(this),amt);
        bt.funded += amt;
        bt.funders[msg.sender] += amt;
        emit Bounty_Funded(msg.sender, _id, amt);
    }
    
    function Unlock_Milestone(uint256 prop_id, uint256 msno, address bene) public{
        Bounty storage bt = bounties[prop_id];
        
        require(bt.liquidated == false,"Unlock_Milestone: Proposal liquidated");
        require(msno <= bt.msvalues.length, "Unlock_Milestone: Invalid Milestone No");
        require(bt.has_voted[msg.sender][msno] == false,  "Unlock_Milestone:You have already voted this milestone");
        require(bt.funded>= bt.paid_out+bt.msvalues[msno -1] , "Unlock_Milestone: Bounty not enough funding");
        require(bt.funders[msg.sender] > 0, "Unlock_Milestone: Not a funder.");
        require(bt.mspayout[msno] == false, "Unlock_Milestone: Milestone already paid out");
        bt.msvotes[msno] += bt.funders[msg.sender]; // Add voters votes to milestone total
        bt.has_voted[msg.sender][msno] == true;  // Prevent double voting
        
        if(bt.msvotes[msno] > (bt.funded/2)){ // Initiate transfer of funds after milestone quorum is reached
            bt.mspayout[msno] = true;     //Add milestone completed
            bt.paid_out += bt.msvalues[msno-1];     //Add payment to total paid out balance 
            emit Milestone_Unlocked(prop_id, msno);
            Token(_token).transfer(bene, bt.msvalues[msno-1]);
        }
    }    

    function Refund_Bounty(uint256 bt_id) public{ 
        Bounty storage bt = bounties[bt_id];
        require(bt.funded > 0, "Refund_Bounty: Proposal not funded");
        require((bt.duration+bt.start) < block.timestamp, "Refund_Bounty: Not yet able to return funds");
        require(bt.funders[msg.sender] > 0, "Refund_Bounty: Not a funder");
        uint256 fract = (bt.funders[msg.sender] * 1000000) / bt.funded;
        uint256 refund = (fract*(bt.funded - bt.paid_out))/1000000;
        bt.funders[msg.sender] = 0; // subtract remaining voting power
        bt.funded -= refund;
        Token(_token).transfer(msg.sender,refund);
        emit Bounty_Refunded(bt_id, msg.sender, refund);
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
}
