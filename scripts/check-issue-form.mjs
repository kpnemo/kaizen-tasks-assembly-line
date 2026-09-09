#!/usr/bin/env node
// Validates .github/ISSUE_TEMPLATE/feature-request.yml: it parses as YAML, is named "Feature request",
// applies the feature-request label, and has exactly the five fields in order with the required ones required.
import { readFileSync } from "node:fs";
import { parse } from "yaml";

const path = new URL("../.github/ISSUE_TEMPLATE/feature-request.yml", import.meta.url);
let doc;
try {
  doc = parse(readFileSync(path, "utf8"));
} catch (error) {
  console.error(`feature-request.yml: FAILED to read or parse: ${error.message}`);
  process.exit(1);
}

const expectedIds = ["problem", "behavior", "acceptance", "out_of_scope", "role"];
const requiredIds = ["problem", "behavior", "acceptance"];
const fields = (doc.body ?? []).filter((block) => block.type !== "markdown");
const ids = fields.map((block) => block.id);
const problems = [];

if (doc.name !== "Feature request") {
  problems.push(`name is ${JSON.stringify(doc.name)}, expected "Feature request"`);
}
if (!Array.isArray(doc.labels) || !doc.labels.includes("feature-request")) {
  problems.push(`labels must include "feature-request", got ${JSON.stringify(doc.labels)}`);
}
if (JSON.stringify(ids) !== JSON.stringify(expectedIds)) {
  problems.push(`field ids are ${JSON.stringify(ids)}, expected ${JSON.stringify(expectedIds)}`);
}
for (const field of fields) {
  const required = Boolean(field.validations?.required);
  const shouldBeRequired = requiredIds.includes(field.id);
  if (required !== shouldBeRequired) {
    problems.push(`${field.id} required=${required}, expected ${shouldBeRequired}`);
  }
  if (!field.attributes?.label) {
    problems.push(`${field.id} has no label`);
  }
}
const roleField = fields.find((field) => field.id === "role");
if (roleField && roleField.type !== "input") {
  problems.push(`role must be an input, got ${roleField.type}`);
}
for (const field of fields.filter((f) => f.id !== "role")) {
  if (field.type !== "textarea") {
    problems.push(`${field.id} must be a textarea, got ${field.type}`);
  }
}

if (problems.length > 0) {
  console.error("feature-request.yml: FAILED");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(`feature-request.yml: OK (${ids.join(", ")})`);
