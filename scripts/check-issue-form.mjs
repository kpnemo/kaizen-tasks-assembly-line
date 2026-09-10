#!/usr/bin/env node
// Validates the issue forms in .github/ISSUE_TEMPLATE/: each parses as YAML, carries its expected name and
// label, and has exactly its five fields in order, with the required ones required and the right field types.
import { readFileSync } from "node:fs";
import { parse } from "yaml";

const forms = [
  {
    file: "feature-request.yml",
    name: "Feature request",
    label: "feature-request",
    expectedIds: ["problem", "behavior", "acceptance", "out_of_scope", "role"],
    requiredIds: ["problem", "behavior", "acceptance"],
    inputIds: ["role"],
  },
  {
    file: "bug-report.yml",
    name: "Bug report",
    label: "bug",
    expectedIds: ["happened", "expected", "steps", "where", "role"],
    requiredIds: ["happened", "expected", "steps", "where"],
    inputIds: ["where", "role"],
  },
];

let failed = false;

for (const form of forms) {
  const path = new URL(`../.github/ISSUE_TEMPLATE/${form.file}`, import.meta.url);
  let doc;
  try {
    doc = parse(readFileSync(path, "utf8"));
  } catch (error) {
    console.error(`${form.file}: FAILED to read or parse: ${error.message}`);
    failed = true;
    continue;
  }

  const fields = (doc.body ?? []).filter((block) => block.type !== "markdown");
  const ids = fields.map((block) => block.id);
  const problems = [];

  if (doc.name !== form.name) {
    problems.push(`name is ${JSON.stringify(doc.name)}, expected ${JSON.stringify(form.name)}`);
  }
  if (!Array.isArray(doc.labels) || !doc.labels.includes(form.label)) {
    problems.push(
      `labels must include ${JSON.stringify(form.label)}, got ${JSON.stringify(doc.labels)}`,
    );
  }
  if (JSON.stringify(ids) !== JSON.stringify(form.expectedIds)) {
    problems.push(
      `field ids are ${JSON.stringify(ids)}, expected ${JSON.stringify(form.expectedIds)}`,
    );
  }
  for (const field of fields) {
    const required = Boolean(field.validations?.required);
    const shouldBeRequired = form.requiredIds.includes(field.id);
    if (required !== shouldBeRequired) {
      problems.push(`${field.id} required=${required}, expected ${shouldBeRequired}`);
    }
    if (!field.attributes?.label) {
      problems.push(`${field.id} has no label`);
    }
    const expectedType = form.inputIds.includes(field.id) ? "input" : "textarea";
    if (field.type !== expectedType) {
      problems.push(`${field.id} must be a ${expectedType}, got ${field.type}`);
    }
  }

  if (problems.length > 0) {
    console.error(`${form.file}: FAILED`);
    for (const problem of problems) console.error(`  - ${problem}`);
    failed = true;
    continue;
  }
  console.log(`${form.file}: OK (${ids.join(", ")})`);
}

process.exit(failed ? 1 : 0);
