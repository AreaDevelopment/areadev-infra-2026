import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as elasticache from "aws-cdk-lib/aws-elasticache";
import { Construct } from "constructs";

interface CacheStackProps extends cdk.StackProps {
  stage: string;
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
}

export class CacheStack extends cdk.Stack {
  public readonly endpoint: string;

  constructor(scope: Construct, id: string, props: CacheStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";

    const subnetGroup = new elasticache.CfnSubnetGroup(this, "SubnetGroup", {
      description: "ElastiCache subnet group for AreaDev",
      subnetIds: props.vpc.selectSubnets({
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      }).subnetIds,
      cacheSubnetGroupName: `areadev-${props.stage}-redis`,
    });

    const redis = new elasticache.CfnCacheCluster(this, "Redis", {
      engine: "redis",
      cacheNodeType: isProd ? "cache.r7g.large" : "cache.t4g.micro",
      numCacheNodes: 1,
      clusterName: `areadev-${props.stage}-redis`,
      vpcSecurityGroupIds: [props.securityGroup.securityGroupId],
      cacheSubnetGroupName: subnetGroup.cacheSubnetGroupName,
      engineVersion: "7.1",
      port: 6379,
    });

    redis.addDependency(subnetGroup);

    this.endpoint = redis.attrRedisEndpointAddress;

    // Outputs
    new cdk.CfnOutput(this, "RedisEndpoint", {
      value: this.endpoint,
    });
  }
}
