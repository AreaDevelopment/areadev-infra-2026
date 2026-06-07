#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import { VpcStack } from "../lib/vpc-stack";
import { DatabaseStack } from "../lib/database-stack";
import { StorageStack } from "../lib/storage-stack";
import { CacheStack } from "../lib/cache-stack";
import { EtlStack } from "../lib/etl-stack";
import { ApiStack } from "../lib/api-stack";
import { FrontendStack } from "../lib/frontend-stack";
import { CmsStack } from "../lib/cms-stack";

const app = new cdk.App();

const stage = app.node.tryGetContext("stage") || "stage";
const account = app.node.tryGetContext("account") || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext("region") || "us-east-1";
const domain = app.node.tryGetContext("domain") || "areadevelopment.com";

const env: cdk.Environment = { account, region };
const prefix = `areadev-${stage}`;

// ── Foundational Stacks ──────────────────────────────────────

const vpc = new VpcStack(app, `${prefix}-vpc`, { env, stage });

const database = new DatabaseStack(app, `${prefix}-database`, {
  env,
  stage,
  vpc: vpc.vpc,
  securityGroup: vpc.dbSecurityGroup,
});

const storage = new StorageStack(app, `${prefix}-storage`, {
  env,
  stage,
  domain,
});

const cache = new CacheStack(app, `${prefix}-cache`, {
  env,
  stage,
  vpc: vpc.vpc,
  securityGroup: vpc.cacheSecurityGroup,
});

// ── Application Stacks ───────────────────────────────────────

new EtlStack(app, `${prefix}-etl`, {
  env,
  stage,
  vpc: vpc.vpc,
  securityGroup: vpc.lambdaSecurityGroup,
  databaseSecret: database.secret,
  databaseEndpoint: database.clusterEndpoint,
});

new ApiStack(app, `${prefix}-api`, {
  env,
  stage,
  domain,
  vpc: vpc.vpc,
  securityGroup: vpc.lambdaSecurityGroup,
  databaseSecret: database.secret,
  databaseEndpoint: database.clusterEndpoint,
});

new FrontendStack(app, `${prefix}-frontend`, {
  env,
  stage,
  domain,
  assetsBucket: storage.assetsBucket,
});

new CmsStack(app, `${prefix}-cms`, {
  env,
  stage,
  domain,
  vpc: vpc.vpc,
  databaseSecret: database.secret,
  databaseEndpoint: database.clusterEndpoint,
  cacheEndpoint: cache.endpoint,
  assetsBucket: storage.assetsBucket,
});

app.synth();
