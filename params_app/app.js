(async function () {
    "use strict";

    /* ───────── Load schema & defaults ───────── */
    const schemaResp = await fetch("../pipeline/default_params_schema.json");
    const schema = await schemaResp.json();

    let defaultParams;
    try {
        const defResp = await fetch("../pipeline/default_params.json");
        let text = await defResp.text();
        // Strip trailing commas (the file has them)
        text = text.replace(/,\s*([}\]])/g, "$1");
        defaultParams = JSON.parse(text);
    } catch {
        defaultParams = buildDefaults(schema);
    }

    /* ───────── AJV validator ───────── */
    const ajv = new ajv7({ allErrors: true, strict: false });
    const validate = ajv.compile(schema);

    /* ───────── Tab switching ───────── */
    document.querySelectorAll(".tab").forEach((btn) => {
        btn.addEventListener("click", () => {
            document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
            document.querySelectorAll(".tab-content").forEach((s) => s.classList.remove("active"));
            btn.classList.add("active");
            document.getElementById("tab-" + btn.dataset.tab).classList.add("active");
        });
    });

    /* ───────── State ───────── */
    let currentValues = structuredClone(defaultParams);

    /* ───────── Resolve $ref ───────── */
    function resolveRef(node) {
        if (!node || typeof node !== "object") return node;
        if (node.$ref) {
            const path = node.$ref.replace(/^#\//, "").split("/");
            let resolved = schema;
            for (const p of path) resolved = resolved[p];
            // Merge sibling properties (like "default") with the resolved ref
            const { $ref, ...rest } = node;
            return { ...resolveRef(resolved), ...rest };
        }
        return node;
    }

    /* ───────── Build default values from schema ───────── */
    function buildDefaults(schemaNode) {
        const node = resolveRef(schemaNode);
        if (!node) return undefined;
        if (node.type === "object" && node.properties) {
            const obj = {};
            for (const [k, v] of Object.entries(node.properties)) {
                const val = buildDefaults(v);
                if (val !== undefined) obj[k] = val;
            }
            return Object.keys(obj).length ? obj : {};
        }
        if ("default" in node) return structuredClone(node.default);
        return undefined;
    }

    /* ───────── DOM helpers ───────── */
    function el(tag, attrs, ...children) {
        const e = document.createElement(tag);
        if (attrs) for (const [k, v] of Object.entries(attrs)) {
            if (k === "class") e.className = v;
            else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
            else e.setAttribute(k, v);
        }
        for (const c of children) {
            if (typeof c === "string") e.appendChild(document.createTextNode(c));
            else if (c) e.appendChild(c);
        }
        return e;
    }

    /* ───────── Deep get / set ───────── */
    function deepGet(obj, path) {
        let cur = obj;
        for (const p of path) {
            if (cur == null || typeof cur !== "object") return undefined;
            cur = cur[p];
        }
        return cur;
    }
    function deepSet(obj, path, value) {
        let cur = obj;
        for (let i = 0; i < path.length - 1; i++) {
            if (!(path[i] in cur) || typeof cur[path[i]] !== "object") cur[path[i]] = {};
            cur = cur[path[i]];
        }
        cur[path[path.length - 1]] = value;
    }

    /* ───────── Render the form ───────── */
    const formRoot = document.getElementById("form-root");

    function renderForm() {
        formRoot.innerHTML = "";
        const props = schema.properties;
        for (const [key, propSchema] of Object.entries(props)) {
            const resolved = resolveRef(propSchema);
            const section = renderSection(key, resolved, [key]);
            formRoot.appendChild(section);
        }
    }

    function renderSection(label, schemaNode, path) {
        const node = resolveRef(schemaNode);
        const wrapper = el("div", { class: "section collapsed" });
        const header = el("div", { class: "section-header" },
            el("span", { class: "arrow" }, "▼"),
            el("span", null, label)
        );
        if (node.description) {
            header.appendChild(el("span", { class: "desc", style: "font-weight:400;font-size:.78rem;color:#6b7280;margin-left:auto;" }, node.description));
        }
        header.addEventListener("click", () => wrapper.classList.toggle("collapsed"));
        wrapper.appendChild(header);

        const body = el("div", { class: "section-body" });
        const nodeTypes = Array.isArray(node.type) ? node.type : [node.type];
        if (nodeTypes.includes("object") && node.properties) {
            for (const [k, v] of Object.entries(node.properties)) {
                const resolved = resolveRef(v);
                const childPath = [...path, k];
                const resolvedTypes = Array.isArray(resolved.type) ? resolved.type : [resolved.type];
                if (resolvedTypes.includes("object") && resolved.properties) {
                    body.appendChild(renderSection(k, resolved, childPath));
                } else {
                    body.appendChild(renderField(k, resolved, childPath));
                }
            }
        }
        wrapper.appendChild(body);
        return wrapper;
    }

    function renderField(label, schemaNode, path) {
        const node = resolveRef(schemaNode);
        const curVal = deepGet(currentValues, path);
        const defVal = deepGet(defaultParams, path);
        const isChanged = JSON.stringify(curVal) !== JSON.stringify(defVal);

        const field = el("div", { class: "field" + (isChanged ? " changed" : "") });
        field.dataset.path = path.join(".");

        const labelEl = el("div", { class: "field-label" },
            el("span", null, label)
        );
        if (node.description) {
            labelEl.appendChild(el("span", { class: "desc" }, node.description));
        }
        field.appendChild(labelEl);

        const inputWrap = el("div", { class: "field-input" });

        const nullable = Array.isArray(node.type) && node.type.includes("null");
        const types = Array.isArray(node.type) ? node.type.filter((t) => t !== "null") : [node.type];
        const primaryType = types[0] || "string";

        if (nullable) {
            const isNull = curVal === null || curVal === undefined;
            const toggle = el("label", { class: "null-toggle" },
                el("input", {
                    type: "checkbox",
                    ...(isNull ? { checked: "" } : {}),
                    onchange: function () {
                        if (this.checked) {
                            deepSet(currentValues, path, null);
                        } else {
                            deepSet(currentValues, path, defVal !== null && defVal !== undefined ? defVal : getTypeDefault(primaryType));
                        }
                        renderForm();
                    }
                }),
                "null"
            );
            inputWrap.appendChild(toggle);
            if (isNull) {
                field.appendChild(inputWrap);
                return field;
            }
        }

        if (node.enum) {
            const select = el("select", {
                onchange: function () {
                    let v = this.value;
                    if (v === "__null__") v = null;
                    else if (primaryType === "number" || primaryType === "integer") v = Number(v);
                    deepSet(currentValues, path, v);
                    markChanged(field, path);
                }
            });
            if (nullable) select.appendChild(el("option", { value: "__null__" }, "(null)"));
            for (const opt of node.enum) {
                if (opt === null) continue;
                const option = el("option", { value: String(opt) }, String(opt));
                if (String(curVal) === String(opt)) option.selected = true;
                select.appendChild(option);
            }
            inputWrap.appendChild(select);
        } else if (primaryType === "boolean") {
            const select = el("select", {
                onchange: function () {
                    deepSet(currentValues, path, this.value === "true");
                    markChanged(field, path);
                }
            });
            select.appendChild(el("option", { value: "true", ...(curVal === true ? { selected: "" } : {}) }, "true"));
            select.appendChild(el("option", { value: "false", ...(curVal === false ? { selected: "" } : {}) }, "false"));
            inputWrap.appendChild(select);
        } else if (primaryType === "array") {
            const ta = el("textarea", {
                value: JSON.stringify(curVal, null, 2),
                oninput: function () {
                    try {
                        const parsed = JSON.parse(this.value);
                        deepSet(currentValues, path, parsed);
                        this.style.borderColor = "";
                        markChanged(field, path);
                    } catch {
                        this.style.borderColor = "#ef4444";
                    }
                }
            });
            ta.value = JSON.stringify(curVal, null, 2);
            inputWrap.appendChild(ta);
        } else if (primaryType === "object") {
            const ta = el("textarea", {
                oninput: function () {
                    try {
                        const parsed = JSON.parse(this.value);
                        deepSet(currentValues, path, parsed);
                        this.style.borderColor = "";
                        markChanged(field, path);
                    } catch {
                        this.style.borderColor = "#ef4444";
                    }
                }
            });
            ta.value = JSON.stringify(curVal ?? {}, null, 2);
            inputWrap.appendChild(ta);
        } else if (primaryType === "integer" || primaryType === "number") {
            const inp = el("input", {
                type: "number",
                value: curVal != null ? String(curVal) : "",
                ...(node.minimum != null ? { min: String(node.minimum) } : {}),
                ...(node.maximum != null ? { max: String(node.maximum) } : {}),
                ...(primaryType === "integer" ? { step: "1" } : { step: "any" }),
                oninput: function () {
                    const v = primaryType === "integer" ? parseInt(this.value, 10) : parseFloat(this.value);
                    if (!isNaN(v)) {
                        deepSet(currentValues, path, v);
                        markChanged(field, path);
                    }
                }
            });
            inputWrap.appendChild(inp);
        } else {
            const inp = el("input", {
                type: "text",
                value: curVal != null ? String(curVal) : "",
                oninput: function () {
                    deepSet(currentValues, path, this.value);
                    markChanged(field, path);
                }
            });
            inputWrap.appendChild(inp);
        }

        field.appendChild(inputWrap);
        return field;
    }

    function getTypeDefault(type) {
        if (type === "string") return "";
        if (type === "number" || type === "integer") return 0;
        if (type === "boolean") return false;
        if (type === "array") return [];
        if (type === "object") return {};
        return null;
    }

    function markChanged(field, path) {
        const defVal = deepGet(defaultParams, path);
        const curVal = deepGet(currentValues, path);
        field.classList.toggle("changed", JSON.stringify(curVal) !== JSON.stringify(defVal));
        updatePreview();
    }

    /* ───────── Live JSON preview ───────── */
    const outputEl = document.getElementById("editor-output");
    function updatePreview() {
        outputEl.textContent = JSON.stringify(currentValues, null, 4);
    }

    /* ───────── Generate output (only non-default values) ───────── */
    function generateOutput(onlyChanged) {
        if (!onlyChanged) return currentValues;
        return diffObjects(defaultParams, currentValues);
    }

    function diffObjects(def, cur) {
        if (typeof cur !== "object" || cur === null || Array.isArray(cur)) {
            return JSON.stringify(def) !== JSON.stringify(cur) ? cur : undefined;
        }
        const result = {};
        for (const key of Object.keys(cur)) {
            const d = diffObjects(def?.[key], cur[key]);
            if (d !== undefined) result[key] = d;
        }
        return Object.keys(result).length ? result : undefined;
    }

    /* ───────── Toolbar actions ───────── */
    document.getElementById("btn-load-defaults").addEventListener("click", () => {
        currentValues = structuredClone(defaultParams);
        renderForm();
        updatePreview();
    });
    document.getElementById("btn-collapse-all").addEventListener("click", () => {
        formRoot.querySelectorAll(".section").forEach((s) => s.classList.add("collapsed"));
    });
    document.getElementById("btn-expand-all").addEventListener("click", () => {
        formRoot.querySelectorAll(".section").forEach((s) => s.classList.remove("collapsed"));
    });

    const chkOnlyChanged = document.getElementById("chk-only-changed");
    chkOnlyChanged.addEventListener("change", () => {
        formRoot.querySelectorAll(".field").forEach((f) => {
            if (chkOnlyChanged.checked) {
                f.style.display = f.classList.contains("changed") ? "" : "none";
            } else {
                f.style.display = "";
            }
        });
    });

    document.getElementById("btn-download").addEventListener("click", () => {
        const json = JSON.stringify(currentValues, null, 4);
        downloadJSON(json, "params.json");
    });
    document.getElementById("btn-copy").addEventListener("click", () => {
        const json = JSON.stringify(currentValues, null, 4);
        navigator.clipboard.writeText(json).then(() => {
            const btn = document.getElementById("btn-copy");
            btn.textContent = "Copied!";
            setTimeout(() => (btn.textContent = "Copy"), 1500);
        });
    });
    document.getElementById("file-import").addEventListener("change", function () {
        const file = this.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            try {
                let text = reader.result;
                text = text.replace(/,\s*([}\]])/g, "$1");
                currentValues = JSON.parse(text);
                renderForm();
                updatePreview();
            } catch (e) {
                alert("Invalid JSON: " + e.message);
            }
        };
        reader.readAsText(file);
        this.value = "";
    });

    /* ───────── Validate tab ───────── */
    const validateInput = document.getElementById("validate-input");
    const validateResult = document.getElementById("validate-result");

    document.getElementById("file-validate").addEventListener("change", function () {
        const file = this.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => (validateInput.value = reader.result);
        reader.readAsText(file);
        this.value = "";
    });
    document.getElementById("btn-clear-validate").addEventListener("click", () => {
        validateInput.value = "";
        validateResult.classList.add("hidden");
    });
    document.getElementById("btn-validate").addEventListener("click", () => {
        validateResult.classList.remove("hidden");
        let data;
        try {
            let text = validateInput.value;
            text = text.replace(/,\s*([}\]])/g, "$1");
            data = JSON.parse(text);
        } catch (e) {
            validateResult.innerHTML = `<span class="invalid-badge">✗ Invalid JSON</span><p style="margin-top:.4rem">${escapeHtml(e.message)}</p>`;
            return;
        }
        const valid = validate(data);
        if (valid) {
            validateResult.innerHTML = '<span class="valid-badge">✓ Valid</span><p style="margin-top:.4rem;color:#6b7280;">The JSON conforms to the pipeline parameter schema.</p>';
        } else {
            let html = '<span class="invalid-badge">✗ Validation Errors</span><ul class="error-list">';
            for (const err of validate.errors) {
                const path = err.instancePath || "/";
                html += `<li><span class="error-path">${escapeHtml(path)}</span> — <span class="error-msg">${escapeHtml(err.message)}</span></li>`;
            }
            html += "</ul>";
            validateResult.innerHTML = html;
        }
    });

    /* ───────── Utilities ───────── */
    function downloadJSON(json, filename) {
        const blob = new Blob([json], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
    }

    function escapeHtml(s) {
        const div = document.createElement("div");
        div.textContent = s;
        return div.innerHTML;
    }

    /* ───────── Init ───────── */
    renderForm();
    updatePreview();
})();
