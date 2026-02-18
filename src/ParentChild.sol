// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import necessary contracts
// Ensure Counter.sol path is correct for your setup. If using OZ's, use that path.
// Assuming local Counter.sol for this example:
import "./Counter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ScalableHierarchyManagerExpanded
 * @notice Manages a three-level hierarchy (Grandparent->Parent->Child)
 * with minimal core data on-chain and numerous attributes stored
 * off-chain, referenced by hashes in flexible mappings.
 * @dev Uses Counters for safe ID generation. Designed for scalability
 * with large, conceptually nested data structures by flattening keys.
 * Enables efficient single-attribute reads and bulk updates via arrays.
 * Relies on off-chain indexing of emitted events for full state reconstruction.
 * @custom:timestamp Wednesday, April 9, 2025 at 9:56 PM WITA (Ubud, Bali).
 */
contract ScalableHierarchyManagerExpanded is Ownable {
    using Counters for Counters.Counter;

    // --- Structs for Core On-Chain Data (Keep Simple!) ---
    struct Grandparent {
        bool exists; // Flag to check if the ID represents a valid entity
    }

    struct Parent {
        bool exists;
        uint256 grandparentId; // Link to the Grandparent entity
    }

    struct Child {
        bool exists;
        uint256 parentId; // Link to the Parent entity
    }

    // --- Storage for Core Data ---
    Counters.Counter private _grandparentIdCounter;
    Counters.Counter private _parentIdCounter;
    Counters.Counter private _childIdCounter;

    mapping(uint256 => Grandparent) private _grandparents;
    mapping(uint256 => Parent) private _parents;
    mapping(uint256 => Child) private _children;

    // --- Storage for Attributes ---
    // Stores attribute hashes (or small values) keyed by entity ID and attribute path hash.
    // Format: mapping(entityId => mapping(attributeKey => attributeValueHash))
    mapping(uint256 => mapping(bytes32 => bytes32)) private _grandparentAttributes;
    mapping(uint256 => mapping(bytes32 => bytes32)) private _parentAttributes;
    mapping(uint256 => mapping(bytes32 => bytes32)) private _childAttributes;

    // --- Events ---
    event GrandparentCreated(uint256 indexed id, address creator);
    event ParentCreated(uint256 indexed id, uint256 indexed grandparentId, address creator);
    event ChildCreated(uint256 indexed id, uint256 indexed parentId, address creator);

    // Events for tracking individual attribute changes, crucial for off-chain indexing
    event GrandparentAttributeSet(uint256 indexed id, bytes32 indexed key, bytes32 value);
    event ParentAttributeSet(uint256 indexed id, bytes32 indexed key, bytes32 value);
    event ChildAttributeSet(uint256 indexed id, bytes32 indexed key, bytes32 value);

    // --- Constructor ---
    constructor(address initialOwner) Ownable(initialOwner) {}

    // --- Grandparent Management Functions ---
    function createGrandparent(bytes32[] calldata _attributeKeys, bytes32[] calldata _attributeValues)
        external
        onlyOwner
        returns (uint256)
    {
        require(_attributeKeys.length == _attributeValues.length, "Keys/values length mismatch");

        _grandparentIdCounter.increment();
        uint256 newId = _grandparentIdCounter.current();

        _grandparents[newId] = Grandparent({exists: true});
        emit GrandparentCreated(newId, msg.sender);

        _setAttributesForGrandparent(newId, _attributeKeys, _attributeValues);
        return newId;
    }

    function setGrandparentAttributes(uint256 _id, bytes32[] calldata _keys, bytes32[] calldata _values)
        external
        onlyOwner
    {
        require(_grandparents[_id].exists, "GP not found");
        require(_keys.length == _values.length, "Keys/values length mismatch");
        _setAttributesForGrandparent(_id, _keys, _values);
    }

    // --- Parent Management Functions ---
    function createParent(
        uint256 _grandparentId,
        bytes32[] calldata _attributeKeys,
        bytes32[] calldata _attributeValues
    ) external onlyOwner returns (uint256) {
        require(_grandparents[_grandparentId].exists, "GP does not exist");
        require(_attributeKeys.length == _attributeValues.length, "Keys/values length mismatch");

        _parentIdCounter.increment();
        uint256 newId = _parentIdCounter.current();

        _parents[newId] = Parent({exists: true, grandparentId: _grandparentId});
        emit ParentCreated(newId, _grandparentId, msg.sender);

        _setAttributesForParent(newId, _attributeKeys, _attributeValues);
        return newId;
    }

    function setParentAttributes(uint256 _id, bytes32[] calldata _keys, bytes32[] calldata _values)
        external
        onlyOwner
    {
        require(_parents[_id].exists, "Parent not found");
        require(_keys.length == _values.length, "Keys/values length mismatch");
        _setAttributesForParent(_id, _keys, _values);
    }

    // --- Child Management Functions ---
    function createChild(uint256 _parentId, bytes32[] calldata _attributeKeys, bytes32[] calldata _attributeValues)
        external
        onlyOwner
        returns (uint256)
    {
        require(_parents[_parentId].exists, "Parent does not exist");
        require(_attributeKeys.length == _attributeValues.length, "Keys/values length mismatch");

        _childIdCounter.increment();
        uint256 newId = _childIdCounter.current();

        _children[newId] = Child({exists: true, parentId: _parentId});
        emit ChildCreated(newId, _parentId, msg.sender);

        _setAttributesForChild(newId, _attributeKeys, _attributeValues);
        return newId;
    }

    function setChildAttributes(uint256 _id, bytes32[] calldata _keys, bytes32[] calldata _values) external onlyOwner {
        require(_children[_id].exists, "Child not found");
        require(_keys.length == _values.length, "Keys/values length mismatch");
        _setAttributesForChild(_id, _keys, _values);
    }

    // --- Getter Functions ---

    // Get single attribute value for a Grandparent
    function getGrandparentAttribute(uint256 _id, bytes32 _key) external view returns (bytes32) {
        require(_grandparents[_id].exists, "GP not found");
        return _grandparentAttributes[_id][_key]; // Returns bytes32(0) if key not set
    }

    // Get single attribute value for a Parent
    function getParentAttribute(uint256 _id, bytes32 _key) external view returns (bytes32) {
        require(_parents[_id].exists, "Parent not found");
        return _parentAttributes[_id][_key]; // Returns bytes32(0) if key not set
    }

    // Get single attribute value for a Child
    function getChildAttribute(uint256 _id, bytes32 _key) external view returns (bytes32) {
        require(_children[_id].exists, "Child not found");
        return _childAttributes[_id][_key]; // Returns bytes32(0) if key not set
    }

    // Get core on-chain info for a Grandparent
    function getGrandparentInfo(uint256 _id) external view returns (Grandparent memory) {
        require(_grandparents[_id].exists, "GP not found");
        return _grandparents[_id];
    }

    // Get core on-chain info for a Parent
    function getParentInfo(uint256 _id) external view returns (Parent memory) {
        require(_parents[_id].exists, "Parent not found");
        return _parents[_id];
    }

    // Get core on-chain info for a Child
    function getChildInfo(uint256 _id) external view returns (Child memory) {
        require(_children[_id].exists, "Child not found");
        return _children[_id];
    }

    // --- Internal Helper Functions ---
    // These handle the iteration and storage writes for attributes

    function _setAttributesForGrandparent(uint256 _id, bytes32[] memory _keys, bytes32[] memory _values) private {
        mapping(bytes32 => bytes32) storage attributes = _grandparentAttributes[_id];
        for (uint256 i = 0; i < _keys.length; i++) {
            attributes[_keys[i]] = _values[i];
            emit GrandparentAttributeSet(_id, _keys[i], _values[i]);
        }
    }

    function _setAttributesForParent(uint256 _id, bytes32[] memory _keys, bytes32[] memory _values) private {
        mapping(bytes32 => bytes32) storage attributes = _parentAttributes[_id];
        for (uint256 i = 0; i < _keys.length; i++) {
            attributes[_keys[i]] = _values[i];
            emit ParentAttributeSet(_id, _keys[i], _values[i]);
        }
    }

    function _setAttributesForChild(uint256 _id, bytes32[] memory _keys, bytes32[] memory _values) private {
        mapping(bytes32 => bytes32) storage attributes = _childAttributes[_id];
        for (uint256 i = 0; i < _keys.length; i++) {
            attributes[_keys[i]] = _values[i];
            emit ChildAttributeSet(_id, _keys[i], _values[i]);
        }
    }

    // --- Optional: Encoded Data Functions ---
    // Alternative way to create entities if preferred over passing arrays directly

    function createParentEncoded(uint256 _grandparentId, bytes calldata _encodedAttributes)
        external
        onlyOwner
        returns (uint256)
    {
        require(_grandparents[_grandparentId].exists, "GP does not exist");
        (bytes32[] memory keys, bytes32[] memory values) = abi.decode(_encodedAttributes, (bytes32[], bytes32[]));
        require(keys.length == values.length, "Decoded keys/values mismatch");

        _parentIdCounter.increment();
        uint256 newId = _parentIdCounter.current();

        _parents[newId] = Parent({exists: true, grandparentId: _grandparentId});
        emit ParentCreated(newId, _grandparentId, msg.sender);

        _setAttributesForParent(newId, keys, values);
        return newId;
    }
    // Add createGrandparentEncoded, createChildEncoded if needed...
}
