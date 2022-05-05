# PharmaLedger_funding
This repo contains the smart contracts for a blockchain based environment for funding projects and posting projects on a bounty board. It was designed by Team Novartis of the 2022 Blockchain Challenge hosted by the University of Basel.
The system consists of three smart contracts: a basic ERC-20 token used for paying the contracts, a bounty board contract where bounties can be funded by multiple parties and a funding round contest that facilitates the aggregation and distribution of funds. 

The funding round uses "radical" voting which returns reduced voting power in return for funds above a initially defined soft-cap. The voting power delivered above the funding contract is calculated by (funding above softcap)**exponent_1 * softcap**exponent_2

Addtionally this repo contains 2 Jupyter notebooks used for calculating the "Danger Zone" maximum(Maximum at which funding above softcap returns more voting power than funding delivered) and testing the deployed contracts.

Check the wiki for more info.
