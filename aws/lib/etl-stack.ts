import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";

interface EtlStackProps extends cdk.StackProps {
  stage: string;
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
  databaseSecret: secretsmanager.ISecret;
  databaseEndpoint: string;
}

export class EtlStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EtlStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";

    const fn = new lambda.Function(this, "SyncFunction", {
      functionName: `areadev-${props.stage}-etl-sync`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: "src/lambda/handler.handler",
      code: lambda.Code.fromAsset("../placeholder"), // Replaced during deploy
      memorySize: isProd ? 1024 : 512,
      timeout: cdk.Duration.minutes(10),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [props.securityGroup],
      environment: {
        NODE_ENV: "production",
        DB_HOST: props.databaseEndpoint,
        DB_PORT: "5432",
        DB_SECRET_ARN: props.databaseSecret.secretArn,
        STAGE: props.stage,
      },
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    // Grant read access to database secret
    props.databaseSecret.grantRead(fn);

    // EventBridge schedule — every 6 hours
    const schedule = isProd ? "rate(6 hours)" : "rate(12 hours)";
    new events.Rule(this, "SyncSchedule", {
      ruleName: `areadev-${props.stage}-etl-schedule`,
      schedule: events.Schedule.expression(schedule),
      targets: [new targets.LambdaFunction(fn)],
    });

    // Outputs
    new cdk.CfnOutput(this, "FunctionArn", { value: fn.functionArn });
  }
}
