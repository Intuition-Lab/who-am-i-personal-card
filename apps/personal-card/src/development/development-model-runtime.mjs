import { FixtureProvider } from "../providers/fixture-provider.mjs";

const OWNER_MODEL_ID = "cecilia";
const SHARED_MODEL_ID = "lin-demo";

export function createDevelopmentModelRuntime() {
  const provider = new FixtureProvider();
  return Object.freeze({
    ownerModelId: OWNER_MODEL_ID,
    providers: Object.freeze({
      [OWNER_MODEL_ID]: provider,
      [SHARED_MODEL_ID]: provider,
    }),
    isOwnerModel(modelId) {
      return modelId === OWNER_MODEL_ID;
    },
    isPubliclyReadable(modelId) {
      return modelId === OWNER_MODEL_ID || modelId === SHARED_MODEL_ID;
    },
    async createGrant({ modelId, grantTokenService }) {
      if (modelId !== SHARED_MODEL_ID) return null;
      const snapshot = await provider.getSnapshot(modelId);
      return grantTokenService.sign({
        grantId: `dev_${modelId}_${Date.now()}`,
        modelId,
        scopes: snapshot.authorization.scopes,
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        audience: "personal-card-v5",
      });
    },
  });
}
