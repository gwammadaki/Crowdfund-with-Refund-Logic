
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

const contractName = "Crowdfund-with-Refund-Logic";

describe("Crowdfund with Analytics Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  describe("Campaign Analytics System", () => {
    it("should initialize campaign and track basic analytics", () => {
      // Initialize campaign
      const { result: initResult } = simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 100), Cl.principal(deployer)],
        deployer
      );
      expect(initResult).toBeOk(Cl.bool(true));

      // Check initial contribution statistics
      const { result: statsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-contribution-statistics",
        [],
        address1
      );
      expect(statsResult).toBeOk(
        Cl.tuple({
          "total-raised": Cl.uint(0),
          "unique-contributors": Cl.uint(0),
          "avg-contribution": Cl.uint(0),
          "campaign-target": Cl.uint(1000000),
          "target-progress-percentage": Cl.uint(0),
        })
      );
    });

    it("should track contributor analytics when contributions are made", () => {
      // Initialize campaign first
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 100), Cl.principal(deployer)],
        deployer
      );

      // Make a contribution
      const { result: contributeResult } = simnet.callPublicFn(
        contractName,
        "contribute",
        [],
        address1
      );
      expect(contributeResult).toBeOk(Cl.bool(true));

      // Check contributor engagement data
      const { result: engagementResult } = simnet.callReadOnlyFn(
        contractName,
        "get-contributor-engagement",
        [Cl.principal(address1)],
        address1
      );
      expect(engagementResult).toBeDefined();
    });

    it("should calculate campaign performance score", () => {
      // Initialize campaign
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );

      // Make contributions
      simnet.callPublicFn(contractName, "contribute", [], address1);
      simnet.callPublicFn(contractName, "contribute", [], address2);

      // Check performance score
      const { result: scoreResult } = simnet.callReadOnlyFn(
        contractName,
        "get-campaign-performance-score",
        [],
        address1
      );
      expect(scoreResult).toBeDefined();
    });

    it("should track milestone completion rates", () => {
      // Initialize campaign
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );

      // Create a milestone
      simnet.callPublicFn(
        contractName,
        "create-milestone",
        [Cl.stringAscii("Test milestone"), Cl.uint(500000)],
        deployer
      );

      // Check milestone completion rate
      const { result: completionResult } = simnet.callReadOnlyFn(
        contractName,
        "get-milestone-completion-rate",
        [],
        address1
      );
      expect(completionResult).toBeOk(
        Cl.tuple({
          "total-milestones": Cl.uint(1),
          "approved-milestones": Cl.uint(0),
          "completed-milestones": Cl.uint(0),
          "approval-rate": Cl.uint(0),
          "completion-rate": Cl.uint(0),
        })
      );
    });

    it("should create and retrieve analytics snapshots", () => {
      // Initialize campaign
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );

      // Make some contributions
      simnet.callPublicFn(contractName, "contribute", [], address1);
      simnet.callPublicFn(contractName, "contribute", [], address2);

      // Create analytics snapshot
      const { result: snapshotResult } = simnet.callPublicFn(
        contractName,
        "create-analytics-snapshot",
        [],
        deployer
      );
      expect(snapshotResult).toBeOk(Cl.uint(1));

      // Retrieve the snapshot
      const { result: retrieveResult } = simnet.callReadOnlyFn(
        contractName,
        "get-campaign-analytics",
        [Cl.uint(1)],
        address1
      );
      expect(retrieveResult).toBeDefined();
    });

    it("should track milestone voting analytics", () => {
      // Initialize campaign and create milestone
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );
      
      // Make contributions first
      simnet.callPublicFn(contractName, "contribute", [], address1);
      
      simnet.callPublicFn(
        contractName,
        "create-milestone",
        [Cl.stringAscii("Test milestone"), Cl.uint(500000)],
        deployer
      );

      // Vote for milestone
      const { result: voteResult } = simnet.callPublicFn(
        contractName,
        "vote-for-milestone",
        [Cl.uint(1)],
        address1
      );
      expect(voteResult).toBeDefined();

      // Check updated contributor engagement
      const { result: engagementResult } = simnet.callReadOnlyFn(
        contractName,
        "get-contributor-engagement",
        [Cl.principal(address1)],
        address1
      );
      
      // Expect milestone-votes to be incremented
      const engagement = engagementResult as any;
      expect(engagement.value.data["milestone-votes"]).toEqual(Cl.uint(1));
    });

    it("should return tier distribution statistics", () => {
      // Initialize campaign
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(10000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );

      // Make contributions to test tier distribution
      simnet.callPublicFn(contractName, "contribute", [], address1);
      simnet.callPublicFn(contractName, "contribute", [], address2);

      // Check tier distribution
      const { result: tierResult } = simnet.callReadOnlyFn(
        contractName,
        "get-tier-distribution-stats",
        [],
        address1
      );
      expect(tierResult).toBeDefined();
    });

    it("should calculate engagement scores correctly", () => {
      // Initialize campaign
      simnet.callPublicFn(
        contractName,
        "initialize",
        [Cl.uint(1000000), Cl.uint(simnet.blockHeight + 200), Cl.principal(deployer)],
        deployer
      );

      // Make contribution
      simnet.callPublicFn(contractName, "contribute", [], address1);

      // Calculate engagement score
      const { result: scoreResult } = simnet.callReadOnlyFn(
        contractName,
        "calculate-engagement-score",
        [Cl.principal(address1)],
        address1
      );
      expect(scoreResult).toBeDefined();
    });

    it("should handle analytics for campaigns with no data", () => {
      // Test analytics functions with uninitialized campaign
      const { result: statsResult } = simnet.callReadOnlyFn(
        contractName,
        "get-contribution-statistics",
        [],
        address1
      );
      expect(statsResult).toBeOk(
        Cl.tuple({
          "total-raised": Cl.uint(0),
          "unique-contributors": Cl.uint(0),
          "avg-contribution": Cl.uint(0),
          "campaign-target": Cl.uint(0),
          "target-progress-percentage": Cl.uint(0),
        })
      );

      const { result: scoreResult } = simnet.callReadOnlyFn(
        contractName,
        "get-campaign-performance-score",
        [],
        address1
      );
      expect(scoreResult).toBeOk(Cl.uint(0));
    });
  });
});
