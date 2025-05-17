// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

interface IIdentityRouter {
    struct RouterConfig {
        string childName;
        bool useChildWallet;
    }

    /**
     * getRouterConfig Returns the router configuration for a given parent identity and validator id.
     * @param _parentIdentityName Parent identity name
     * @param _validatorId Validator id
     * @return RouterConfig_ Router configuration tuple(string childName, boolean useChildWallet)
     */
    function getRouterConfig(string calldata _parentIdentityName, uint32 _validatorId)
        external
        view
        returns (RouterConfig memory);
}
