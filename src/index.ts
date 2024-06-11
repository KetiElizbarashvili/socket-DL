import { DeploymentMode } from "./socket-types";
export { finality } from "../scripts/rpcConfig/constants/finality";
export * from "./socket-types";
export * from "./enums";
export * from "./addresses";
export * from "./currency-util";

export const version = {
  [DeploymentMode.DEV]: "IMLI",
  [DeploymentMode.SURGE]: "IMLI",
  [DeploymentMode.PROD]: "IMLI",
};
