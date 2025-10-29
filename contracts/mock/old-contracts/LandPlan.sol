// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LandPlan {
    struct Plan {
        uint256 uvmPerDnm;
        uint256 uvmPerLand;
    }

    mapping(uint16 => Plan) internal plans_12;
    mapping(uint16 => Plan) internal plans_18;
    mapping(uint16 => Plan) internal plans_24;

    constructor(){
        // all plans are calculated on daily profit
        //12 month plan initialization 55% yearly profit calculated daily
        plans_12[1] = Plan({
            uvmPerDnm: 1.07 ether, // 1.07
            uvmPerLand: 3 ether // 3
        });
        plans_12[2] = Plan({
            uvmPerDnm: 1.07 ether, // 1.07
            uvmPerLand: 1.5 ether // 1.5
        });
        plans_12[3] = Plan({
            uvmPerDnm: 1.07 ether, // 1.07
            uvmPerLand: 0.75 ether // 0.75
        });
        plans_12[4] = Plan({
            uvmPerDnm: 1.07 ether, // 1.07
            uvmPerLand: 0.3 ether // 0.3
        });
        plans_12[5] = Plan({
            uvmPerDnm: 1.07 ether, // 1.07
            uvmPerLand: 0.15 ether // 0.15
        });

        //18 month plan initialization 82.5% yearly profit calculated daily
        plans_18[1] = Plan({
            uvmPerDnm: 1.61 ether, // 1.61
            uvmPerLand: 4.5 ether // 4.5
        });

        plans_18[2] = Plan({
            uvmPerDnm: 1.61 ether, // 1.61
            uvmPerLand: 2.25 ether // 2.25
        });

        plans_18[3] = Plan({
            uvmPerDnm: 1.61 ether, // 1.61
            uvmPerLand: 1.12 ether // 1.12
        });

        plans_18[4] = Plan({
            uvmPerDnm: 1.61 ether, // 1.61
            uvmPerLand: 0.45 ether // 0.45
        });

        plans_18[5] = Plan({
            uvmPerDnm: 1.61 ether, // 1.61
            uvmPerLand: 0.225 ether // 0.225
        });

        //24 month plan initialization 110% yearly profit calculated daily
        plans_24[1] = Plan({
            uvmPerDnm: 2.15 ether, // 2.15
            uvmPerLand: 6 ether // 6
        });

        plans_24[2] = Plan({
            uvmPerDnm: 2.15 ether, // 2.15
            uvmPerLand: 3 ether // 3
        });

        plans_24[3] = Plan({
            uvmPerDnm: 2.15 ether, // 2.15
            uvmPerLand: 1.5 ether //1.5
        });

        plans_24[4] = Plan({
            uvmPerDnm: 2.15 ether, // 2.15
            uvmPerLand: 0.6 ether //0.6
        });

        plans_24[5] = Plan({
            uvmPerDnm: 2.15 ether, // 2.15
            uvmPerLand: 0.3 ether //0.3
        });
    }

}
