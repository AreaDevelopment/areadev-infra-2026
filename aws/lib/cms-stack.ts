import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecs from "aws-cdk-lib/aws-ecs";
import * as ecsPatterns from "aws-cdk-lib/aws-ecs-patterns";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import * as logs from "aws-cdk-lib/aws-logs";
import { Construct } from "constructs";

interface CmsStackProps extends cdk.StackProps {
  stage: string;
  domain: string;
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
  databaseSecret: secretsmanager.ISecret;
  databaseEndpoint: string;
  cacheEndpoint: string;
  assetsBucket: s3.IBucket;
}

export class CmsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: CmsStackProps) {
    super(scope, id, props);

    const isProd = props.stage === "prod";
    const cmsDomain = isProd ? `cms.${props.domain}` : `cms-stage.${props.domain}`;

    const cluster = new ecs.Cluster(this, "Cluster", {
      vpc: props.vpc,
      clusterName: `areadev-${props.stage}-cms`,
    });

    // Directus secret (admin password, app secret, etc.)
    const directusSecret = new secretsmanager.Secret(this, "DirectusSecret", {
      secretName: `areadev/${props.stage}/directus`,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          ADMIN_EMAIL: "admin@areadevelopment.com",
          ADMIN_PASSWORD: "changeme",
        }),
        generateStringKey: "SECRET",
        excludePunctuation: true,
        passwordLength: 32,
      },
    });

    const fargateService = new ecsPatterns.ApplicationLoadBalancedFargateService(
      this,
      "DirectusService",
      {
        cluster,
        serviceName: `areadev-${props.stage}-directus`,
        desiredCount: isProd ? 2 : 1,
        cpu: isProd ? 1024 : 512,
        memoryLimitMiB: isProd ? 2048 : 1024,
        taskImageOptions: {
          image: ecs.ContainerImage.fromRegistry("directus/directus:11.16.0"),
          containerPort: 8055,
          environment: {
            DB_CLIENT: "pg",
            DB_HOST: props.databaseEndpoint,
            DB_PORT: "5432",
            DB_DATABASE: "directus",
            CACHE_ENABLED: "true",
            CACHE_AUTO_PURGE: "true",
            CACHE_STORE: "redis",
            REDIS: `redis://${props.cacheEndpoint}:6379`,
            STORAGE_LOCATIONS: "S3",
            STORAGE_S3_DRIVER: "s3",
            STORAGE_S3_REGION: this.region,
            STORAGE_S3_BUCKET: props.assetsBucket.bucketName,
            MARKETPLACE_TRUST: "all",
          },
          secrets: {
            DB_USER: ecs.Secret.fromSecretsManager(props.databaseSecret, "username"),
            DB_PASSWORD: ecs.Secret.fromSecretsManager(props.databaseSecret, "password"),
            SECRET: ecs.Secret.fromSecretsManager(directusSecret, "SECRET"),
            ADMIN_EMAIL: ecs.Secret.fromSecretsManager(directusSecret, "ADMIN_EMAIL"),
            ADMIN_PASSWORD: ecs.Secret.fromSecretsManager(directusSecret, "ADMIN_PASSWORD"),
          },
          logDriver: ecs.LogDrivers.awsLogs({
            streamPrefix: "directus",
            logRetention: logs.RetentionDays.TWO_WEEKS,
          }),
        },
        securityGroups: [props.securityGroup],
        publicLoadBalancer: true,
        assignPublicIp: false,
      }
    );

    // Auto-scaling
    const scaling = fargateService.service.autoScaleTaskCount({
      minCapacity: isProd ? 2 : 1,
      maxCapacity: isProd ? 4 : 2,
    });

    scaling.scaleOnCpuUtilization("CpuScaling", {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(60),
    });

    // Grant S3 access to the task
    props.assetsBucket.grantReadWrite(fargateService.taskDefinition.taskRole);

    // Health check
    fargateService.targetGroup.configureHealthCheck({
      path: "/server/health",
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
      interval: cdk.Duration.seconds(30),
    });

    // Outputs
    new cdk.CfnOutput(this, "LoadBalancerDns", {
      value: fargateService.loadBalancer.loadBalancerDnsName,
    });
    new cdk.CfnOutput(this, "ExpectedDomain", { value: cmsDomain });
  }
}
