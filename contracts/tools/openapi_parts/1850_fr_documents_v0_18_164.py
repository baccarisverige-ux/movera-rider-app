# Runs inside tools/gen_openapi.py in name order with its globals (rule 25 split). v0.18.164 (France document lists;
# owner 2026-11-25): OnboardingSettings.vehicles.maxAgeYears / hybridElectricExempt (contract.json#driverOnboarding.vehicleRules.maxAge).
_MA = C["driverOnboarding"]["vehicleRules"]["maxAge"]
_LIM = C["driverOnboarding"]["settings"]["limits"]["maxAgeYears"]
_VP = S["OnboardingSettings"]["properties"]["vehicles"]["properties"]
for _k in ("maxAgeYears", "hybridElectricExempt"):
    assert _k not in _VP, "OnboardingSettings.vehicles." + _k + " exists before v0.18.164"
_VP["maxAgeYears"] = i("v0.18.164: the oldest a car may be, in years (rolling: current year minus N). Missing = no age rule. " + _MA, minimum=_LIM[0], maximum=_LIM[1])
_VP["hybridElectricExempt"] = {**b("v0.18.164: hybrid and electric cars are exempt from maxAgeYears (not from minYear). Missing = false."), "default": False}
# v0.18.164 (documents.reviewNeedsFile): DocumentSummary.hasFile, so the admin panel shows Open/Approve only with a file.
_DS = S["DocumentSummary"]["properties"]
assert "hasFile" not in _DS, "DocumentSummary.hasFile exists before v0.18.164"
_DS["hasFile"] = b("v0.18.164 (documents.reviewNeedsFile): true when a file is stored for this document (or renewal). Absent from an older server (treat as unknown). " + C["driverOnboarding"]["documents"]["reviewNeedsFile"])
