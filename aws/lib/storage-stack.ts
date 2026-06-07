import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

interface StorageStackProps extends cdk.StackProps {
  stage: string;
  domain: string;
}

export class StorageStack extends cdk.Stack {
  public readonly assetsBucket: s3.IBucket;
  public readonly deploymentBucket: s3.IBucket;

  constructor(scope: Construct, id: string, props: StorageStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";

    // Directus assets bucket
    this.assetsBucket = new s3.Bucket(this, "AssetsBucket", {
      bucketName: `areadev-directus-storage-${props.stage}`,
      publicReadAccess: true,
      blockPublicAccess: new s3.BlockPublicAccess({
        blockPublicAcls: false,
        ignorePublicAcls: false,
        blockPublicPolicy: false,
        restrictPublicBuckets: false,
      }),
      encryption: s3.BucketEncryption.S3_MANAGED,
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: [`https://${props.domain}`, `https://*.${props.domain}`],
          allowedHeaders: ["*"],
          maxAge: 86400,
        },
      ],
      lifecycleRules: [
        {
          id: "cleanup-incomplete-uploads",
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
      versioned: isProd,
      removalPolicy: isProd ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: !isProd,
    });

    // Lambda deployment packages bucket
    this.deploymentBucket = new s3.Bucket(this, "DeploymentBucket", {
      bucketName: `areadev-deployments-${props.stage}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: "expire-old-versions",
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Outputs
    new cdk.CfnOutput(this, "AssetsBucketName", {
      value: this.assetsBucket.bucketName,
    });
    new cdk.CfnOutput(this, "DeploymentBucketName", {
      value: this.deploymentBucket.bucketName,
    });
  }
}
