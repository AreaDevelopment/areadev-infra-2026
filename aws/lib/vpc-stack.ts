import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { Construct } from "constructs";

interface VpcStackProps extends cdk.StackProps {
  stage: string;
}

export class VpcStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly dbSecurityGroup: ec2.ISecurityGroup;
  public readonly cacheSecurityGroup: ec2.ISecurityGroup;
  public readonly lambdaSecurityGroup: ec2.ISecurityGroup;
  public readonly ecsSecurityGroup: ec2.ISecurityGroup;

  constructor(scope: Construct, id: string, props: VpcStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";

    this.vpc = new ec2.Vpc(this, "Vpc", {
      maxAzs: 2,
      natGateways: isProd ? 2 : 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: "public",
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: "private",
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: "isolated",
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Security group for Aurora database
    this.dbSecurityGroup = new ec2.SecurityGroup(this, "DbSg", {
      vpc: this.vpc,
      description: "Aurora PostgreSQL security group",
      allowAllOutbound: false,
    });

    // Security group for ElastiCache Redis
    this.cacheSecurityGroup = new ec2.SecurityGroup(this, "CacheSg", {
      vpc: this.vpc,
      description: "ElastiCache Redis security group",
      allowAllOutbound: false,
    });

    // Security group for Lambda functions
    this.lambdaSecurityGroup = new ec2.SecurityGroup(this, "LambdaSg", {
      vpc: this.vpc,
      description: "Lambda functions security group",
      allowAllOutbound: true,
    });

    // Security group for ECS (Directus)
    this.ecsSecurityGroup = new ec2.SecurityGroup(this, "EcsSg", {
      vpc: this.vpc,
      description: "ECS Fargate security group",
      allowAllOutbound: true,
    });

    // Allow Lambda and ECS to access the database
    this.dbSecurityGroup.addIngressRule(
      this.lambdaSecurityGroup,
      ec2.Port.tcp(5432),
      "Lambda access to Aurora"
    );
    this.dbSecurityGroup.addIngressRule(
      this.ecsSecurityGroup,
      ec2.Port.tcp(5432),
      "ECS access to Aurora"
    );

    // Allow Lambda and ECS to access Redis
    this.cacheSecurityGroup.addIngressRule(
      this.lambdaSecurityGroup,
      ec2.Port.tcp(6379),
      "Lambda access to Redis"
    );
    this.cacheSecurityGroup.addIngressRule(
      this.ecsSecurityGroup,
      ec2.Port.tcp(6379),
      "ECS access to Redis"
    );

    // Outputs
    new cdk.CfnOutput(this, "VpcId", { value: this.vpc.vpcId });
  }
}
