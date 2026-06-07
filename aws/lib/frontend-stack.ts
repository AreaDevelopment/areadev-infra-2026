import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";

interface FrontendStackProps extends cdk.StackProps {
  stage: string;
  domain: string;
  assetsBucket: s3.IBucket;
}

export class FrontendStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: FrontendStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";
    const siteDomain = isProd ? props.domain : `stage.${props.domain}`;

    // Static assets bucket for Nuxt _nuxt/ files
    const staticBucket = new s3.Bucket(this, "StaticBucket", {
      bucketName: `areadev-frontend-static-${props.stage}`,
      publicReadAccess: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      removalPolicy: isProd ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: !isProd,
    });

    // SSR Lambda (Nuxt/Nitro handler)
    const ssrFunction = new lambda.Function(this, "SsrFunction", {
      functionName: `areadev-${props.stage}-frontend-ssr`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: "index.handler",
      code: lambda.Code.fromAsset("./placeholder"),
      memorySize: isProd ? 1024 : 512,
      timeout: cdk.Duration.seconds(30),
      environment: {
        NODE_ENV: "production",
        NITRO_PRESET: "aws-lambda",
        NUXT_PUBLIC_STAGE: props.stage,
      },
      logRetention: logs.RetentionDays.TWO_WEEKS,
    });

    // Lambda Function URL for SSR
    const fnUrl = ssrFunction.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
    });

    // CloudFront distribution
    const distribution = new cloudfront.Distribution(this, "Distribution", {
      defaultBehavior: {
        origin: new origins.FunctionUrlOrigin(fnUrl),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: new cloudfront.CachePolicy(this, "SsrCachePolicy", {
          cachePolicyName: `areadev-${props.stage}-ssr-cache`,
          defaultTtl: cdk.Duration.seconds(0),
          maxTtl: cdk.Duration.hours(1),
          minTtl: cdk.Duration.seconds(0),
          headerBehavior: cloudfront.CacheHeaderBehavior.allowList("Accept", "Accept-Language"),
          queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
          cookieBehavior: cloudfront.CacheCookieBehavior.none(),
        }),
      },
      additionalBehaviors: {
        "/_nuxt/*": {
          origin: origins.S3BucketOrigin.withOriginAccessControl(staticBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        },
      },
      comment: `AreaDev Frontend (${props.stage})`,
    });

    // Outputs
    new cdk.CfnOutput(this, "DistributionDomain", {
      value: distribution.distributionDomainName,
    });
    new cdk.CfnOutput(this, "ExpectedDomain", { value: siteDomain });
    new cdk.CfnOutput(this, "StaticBucketName", { value: staticBucket.bucketName });
  }
}
