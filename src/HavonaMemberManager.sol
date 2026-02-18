// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract HavonaMemberManager is Ownable {
    // Structs
    struct HavonaMemberRole {
        string role;
        bool isActive;
    }

    struct UrdttMemberRole {
        string role;
        bool isActive;
    }

    struct CompanyInformation {
        string name;
        string details;
    }

    struct Member {
        string companyName;
        address memberAddress;
        bool isActive;
        HavonaMemberRole[] havonaMemberRoles;
        UrdttMemberRole[] urdttMemberRoles;
        mapping(address => bool) collaborators;
        CompanyInformation companyInformation;
        string contactDetails;
        string memberPublicKey;
        string renew;
        string certificate;
        string registrationStatus;
    }

    // Mappings
    mapping(address => Member) public members;
    mapping(string => address) public companyNameToAddress;
    mapping(address => mapping(address => bool)) public collaboratorApprovals;

    // Events
    event MemberAdded(address indexed memberAddress, string companyName);
    event MemberAmended(address indexed memberAddress);
    event MemberFinalized(address indexed memberAddress);
    event MemberRevoked(address indexed memberAddress);
    event CollaboratorAdded(address indexed memberAddress, address indexed collaborator);
    event RoleAdded(address indexed memberAddress, string role, bool isHavona);

    address[] public memberAddresses; // Array to store all member addresses

    constructor() Ownable(msg.sender) {}

    function addMember(
        address _memberAddress,
        string memory _companyName,
        CompanyInformation memory _companyInfo,
        string memory _contactDetails,
        string memory _publicKey
    ) public onlyOwner {
        require(members[_memberAddress].memberAddress == address(0), "Member exists");
        require(companyNameToAddress[_companyName] == address(0), "Company name taken");

        Member storage newMember = members[_memberAddress];
        newMember.companyName = _companyName;
        newMember.memberAddress = _memberAddress;
        newMember.isActive = true;
        newMember.companyInformation = _companyInfo;
        newMember.contactDetails = _contactDetails;
        newMember.memberPublicKey = _publicKey;
        newMember.registrationStatus = "PENDING";

        companyNameToAddress[_companyName] = _memberAddress;
        memberAddresses.push(_memberAddress);
        emit MemberAdded(_memberAddress, _companyName);
    }

    function addCollaborator(address _memberAddress, address _collaborator) public onlyOwner {
        require(members[_memberAddress].memberAddress != address(0), "Member not found");
        members[_memberAddress].collaborators[_collaborator] = true;
        emit CollaboratorAdded(_memberAddress, _collaborator);
    }

    function addHavonaMemberRole(address _memberAddress, string memory _role) public onlyOwner {
        require(members[_memberAddress].memberAddress != address(0), "Member not found");
        members[_memberAddress].havonaMemberRoles.push(HavonaMemberRole(_role, true));
        emit RoleAdded(_memberAddress, _role, true);
    }

    function addUrdttMemberRole(address _memberAddress, string memory _role) public onlyOwner {
        require(members[_memberAddress].memberAddress != address(0), "Member not found");
        members[_memberAddress].urdttMemberRoles.push(UrdttMemberRole(_role, true));
        emit RoleAdded(_memberAddress, _role, false);
    }

    function amendMember(address _memberAddress, string memory _companyInformation, string memory _contactDetails)
        public
        onlyOwner
    {
        require(members[_memberAddress].memberAddress != address(0), "Member does not exist");
        require(members[_memberAddress].isActive, "Member is not active");

        Member storage member = members[_memberAddress];
        member.companyInformation.details = _companyInformation;
        member.contactDetails = _contactDetails;

        emit MemberAmended(_memberAddress);
    }

    function finalizeMember(address _memberAddress) public onlyOwner {
        require(members[_memberAddress].memberAddress != address(0), "Member does not exist");
        members[_memberAddress].registrationStatus = "ACTIVE";
        emit MemberFinalized(_memberAddress);
    }

    function revokeMember(address _memberAddress) public onlyOwner {
        require(members[_memberAddress].memberAddress != address(0), "Member does not exist");
        members[_memberAddress].isActive = false;
        members[_memberAddress].registrationStatus = "REVOKED";
        emit MemberRevoked(_memberAddress);
    }

    function getMember(address _memberAddress)
        public
        view
        returns (string memory companyName, bool isActive, string memory registrationStatus)
    {
        Member storage member = members[_memberAddress];
        return (member.companyName, member.isActive, member.registrationStatus);
    }

    function verifyMemberSignature(address _memberAddress, bytes32 _messageHash, bytes memory _signature)
        public
        view
        returns (bool)
    {
        require(members[_memberAddress].memberAddress != address(0), "Member does not exist");
        require(members[_memberAddress].isActive, "Member is not active");

        address recoveredAddress = recoverSigner(_messageHash, _signature);
        return recoveredAddress == _memberAddress;
    }

    function recoverSigner(bytes32 _messageHash, bytes memory _signature) internal pure returns (address) {
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function getAllMemberDetails() external view returns (address[] memory addresses, string[] memory companyNames) {
        uint256 totalMembers = memberAddresses.length;
        addresses = new address[](totalMembers);
        companyNames = new string[](totalMembers);

        for (uint256 i = 0; i < totalMembers; i++) {
            address memberAddress = memberAddresses[i];
            addresses[i] = memberAddress;
            companyNames[i] = members[memberAddress].companyName;
        }

        return (addresses, companyNames);
    }
}
