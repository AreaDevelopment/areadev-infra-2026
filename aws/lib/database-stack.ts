import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as rds from "aws-cdk-lib/aws-rds";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import { Construct } from "constructs";

interface DatabaseStackProps extends cdk.StackProps {
  stage: string;
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
}

export class DatabaseStack extends cdk.Stack {
  public readonly cluster: rds.IDatabaseCluster;
  public readonly secret: secretsmanager.ISecret;
  public readonly clusterEndpoint: string;

  constructor(scope: Construct, id: string, props: DatabaseStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";

    // Database credentials in Secrets Manager
    const credentials = new secretsmanager.Secret(this, "DbCredentials", {
      secretName: `areadev/${props.stage}/database`,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: "directus" }),
        generateStringKey: "password",
        excludePunctuation: true,
        passwordLength: 32,
      },
    });

    this.secret = credentials;

    // Aurora Serverless v2 cluster — PostgreSQL 16
    const cluster = new rds.DatabaseCluster(this, "AuroraCluster", {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_16_4,
      }),
      credentials: rds.Credentials.fromSecret(credentials),
      defaultDatabaseName: "directus",
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
      securityGroups: [props.securityGroup],
      serverlessV2MinCapacity: isProd ? 1 : 0.5,
      serverlessV2MaxCapacity: isProd ? 16 : 4,
      writer: rds.ClusterInstance.serverlessV2("writer", {
        publiclyAccessible: false,
      }),
      readers: isProd
        ? [
            rds.ClusterInstance.serverlessV2("reader", {
              scaleWithWriter: true,
            }),
          ]
        : [],
      backup: {
        retention: cdk.Duration.days(isProd ? 30 : 7),
      },
      storageEncrypted: true,
      deletionProtection: isProd,
      removalPolicy: isProd ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    this.cluster = cluster;
    this.clusterEndpoint = cluster.clusterEndpoint.hostname;

    // Outputs
    new cdk.CfnOutput(this, "ClusterEndpoint", {
      value: cluster.clusterEndpoint.hostname,
    });
    new cdk.CfnOutput(this, "SecretArn", {
      value: credentials.secretArn,
    });
  }
}
