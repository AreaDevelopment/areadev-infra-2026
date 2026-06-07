import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as apigatewayv2 from "aws-cdk-lib/aws-apigatewayv2";
import * as integrations from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";

interface ApiStackProps extends cdk.StackProps {
  stage: string;
  domain: string;
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
  databaseSecret: secretsmanager.ISecret;
  databaseEndpoint: string;
}

export class ApiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";
    const apiDomain = isProd ? `api.${props.domain}` : `api-stage.${props.domain}`;

    const fn = new lambda.Function(this, "ApiFunction", {
      functionName: `areadev-${props.stage}-api`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: "dist/lambda.handler",
      code: lambda.Code.fromAsset("./placeholder"),
      memorySize: isProd ? 1024 : 512,
      timeout: cdk.Duration.seconds(30),
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

    props.databaseSecret.grantRead(fn);

    // HTTP API Gateway
    const httpApi = new apigatewayv2.HttpApi(this, "HttpApi", {
      apiName: `areadev-${props.stage}-api`,
      defaultIntegration: new integrations.HttpLambdaIntegration("LambdaIntegration", fn),
      corsPreflight: {
        allowOrigins: isProd
          ? [`https://${props.domain}`, `https://www.${props.domain}`]
          : ["*"],
        allowMethods: [apigatewayv2.CorsHttpMethod.ANY],
        allowHeaders: ["*"],
        maxAge: cdk.Duration.hours(24),
      },
    });

    // CloudFront distribution
    new cloudfront.Distribution(this, "Distribution", {
      defaultBehavior: {
        origin: new origins.HttpOrigin(
          `${httpApi.httpApiId}.execute-api.${this.region}.amazonaws.com`
        ),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
      },
      comment: `AreaDev API (${props.stage})`,
    });

    // Outputs
    new cdk.CfnOutput(this, "ApiUrl", { value: httpApi.url! });
    new cdk.CfnOutput(this, "ExpectedDomain", { value: apiDomain });
  }
}
