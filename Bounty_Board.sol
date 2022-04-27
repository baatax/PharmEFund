// SPDX-License-Identifier: MIT
/*
Testing results:

*/

//replace block.number with block.timestamp
//Make it accept stable coins
//Make it refund to multiple parties

pragma solidity ^0.8.2;

contract Bounty_Board{

    event Bounty_Posted(address indexed, uint256 indexed,uint256); //Proposer, ID, Costs, Milestones
    event Bounty_Funded(address indexed, uint256 indexed, uint256); // Funder, amount, new voting power
    //event Vote_cast(address indexed, uint256 indexed, uint256, uint256);
    event Milestone_Unlocked(uint256 indexed, uint256, uint256); //Proposal Id, Block, Milestone Nr
    event Bounty_Refunded(uint256 indexed, address indexed, uint256); // Block where vote ended


    struct Bounty {
            bool liquidated;    //Modified by liquidate_proposal
            uint64 start;
            uint64 duration;   //Specified by user
            uint256 reward;  //Amount of funding needed to implement proposal
            uint256 paid_out;   //How much funding has already been paid out
            uint256 funded;
            uint256 msvotes;    //Votes per milestone to release funds (gets reset each milestone)
            bool[] mspayout;    //List that tracks each milestone paid out by adding another entry
            address[] has_voted; // Tracks which funders have already voted
            mapping(address => uint256) funders; // Tracks voting power of funders
            uint256[] msvalues;
        }
    mapping(uint256 => Bounty) bounties; //Datastructure containing all Bounties
    function Refund_Bounty(uint256 prop_id) public{ 
        Bounty storage bt = bounties[prop_id];
        require(bt.funded > 0, "Refund_Bounty: Proposal not funded");
        require((bt.duration+bt.start) < block.number, "Refund_Bounty: Not yet able to return funds");
        require(bt.funders[msg.sender] > 0, "Refund_Bounty: Not a funder");
        uint256 fract = (bt.funders[msg.sender] * 1000000000) / bt.funded;
        uint256 refund = (fract*(bt.funded - bt.paid_out))/100000000;
        bt.funders[msg.sender] = 0; // subtract remaining voting power
        payable(msg.sender).transfer(refund);
        emit Bounty_Refunded(prop_id, msg.sender, refund);
    }

    function Unlock_Milestone(uint256 prop_id, address bene) public{
        Bounty storage bt = bounties[prop_id];
        uint256 btnr = bt.mspayout.length;
        require(bt.liquidated == false,"Unlock_Milestone: Proposal liquidated");
        require(btnr < bt.msvalues.length, "Unlock_Milestone: All milestones already paid out");
        require(_checkVoted(bt, msg.sender) == false,  "Unlock_Milestone:You have already voted this milestone");
        require(bt.funded>= bt.paid_out+bt.msvalues[btnr] , "Unlock_Milestone: Proposal not enough funding");
        require(bt.funders[msg.sender] > 0, "Unlock_Milestone: Not a funder.");
        bt.msvotes += bt.funders[msg.sender]; // Add voters votes to milestone total
        bt.has_voted.push(msg.sender);  // Prevent double voting
        if(bt.msvotes > (bt.funded/2)){ // Initiate transfer of funds after milestone quorum is reached
            bt.mspayout.push(true);     //Add milestone completed
            bt.paid_out += bt.msvalues[btnr];     //Add payment to total paid out balance 
            emit Milestone_Unlocked(prop_id, block.number, btnr);
            delete bt.has_voted;        // Reset Voted list for next milestone
            bt.msvotes = 0;             // Reset votes for new milestone
            payable(bene).transfer(bt.msvalues[btnr]);
        }
    }

    function Post_Bounty(string calldata _salt, uint64 _duration, uint256 _reward, uint256[] calldata _msvalues) public payable returns(uint256) {
        require(_reward == _sumMilestones(_msvalues), "Post_Bounty: msg.value does not correspond with milestone total");
        uint256 _id =  uint256(keccak256(abi.encode(msg.sender, _salt))); //Create unique proposal id
        Bounty storage bt = bounties[_id];   //Create new Proposal struct mapped to proposal Id
        bt.reward = _reward;
        bt.msvalues = _msvalues;
        bt.duration = _duration;
        bt.start = toUint64(block.number);
        bt.funded = msg.value;
        bt.funders[msg.sender] = msg.value;
        emit Bounty_Posted(msg.sender, _id,_reward);

        return _id;
        }
    
    function Fund_Bounty(uint256 _id)public payable{
        Bounty storage bt = bounties[_id];
        require(bt.reward> bt.funded, "Fund_Bounty: Bounty already fully funded");
        require(msg.value > 0 && msg.value <= (bt.reward - bt.funded), "Fund_Bounty: No payment");
        bt.funded += msg.value;
        bt.funders[msg.sender] += msg.value;
        emit Bounty_Funded(msg.sender, _id, msg.value);
    }
    
    

    function _sumMilestones(uint256[] memory mstones)internal pure returns (uint256) {
        uint256 sum;
        for (uint8 i=0; i< mstones.length; i++){
            sum += mstones[i];
        }
        return sum; 
    }

    
    function _checkVoted(Bounty storage bt, address voter) internal view returns(bool){
        for (uint16 i=0; i< bt.has_voted.length; i++){
            if(bt.has_voted[i] == voter){
                return true;
            }
        }
        return false;
    }
    function toUint64(uint256 value) private pure returns (uint64) {
        require(value <= type(uint64).max, "value doesn't fit in 32 bits");
        return uint64(value);
    }
}
