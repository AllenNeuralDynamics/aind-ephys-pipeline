# AIND Ephys Pipeline — Parameter Editor

A browser-based webapp for generating and validating parameter JSON files for the
[AIND Ephys Pipeline](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline).

## Features

### Editor Tab
- **Interactive form** auto-generated from the JSON schema, with proper input widgets
  for each parameter type (dropdowns for enums/booleans, number spinners, textareas
  for arrays/objects, nullable toggles).
- **Inline descriptions** for every parameter.
- **Collapsible sections** matching the schema hierarchy (job_dispatch, preprocessing,
  postprocessing, curation, visualization, nwb, spikesorting).
- **Changed-value highlighting** — modified parameters are shown in blue.
- **"Show only changed"** filter to focus on non-default values.
- **Generate / Download / Copy** the resulting JSON.
- **Import** an existing JSON file to edit it.

### Validate JSON Tab
- Paste or upload a JSON file.
- Validates against the pipeline schema using [AJV](https://ajv.js.org/) with
  detailed error paths and messages.
- Tolerates trailing commas (like the shipped `default_params.json`).

## Quick Start

The app is a static site — no build step or package install required. Just serve the
repository root with any HTTP server:

```bash
# From the repository root
python3 -m http.server 8765

# Then open in your browser
# http://localhost:8765/params_app/
```

The app loads `pipeline/default_params_schema.json` and `pipeline/default_params.json`
via relative paths, so it must be served from the repo root (not from inside `params_app/`).

## Files

| File | Description |
|------|-------------|
| `index.html` | App shell with Editor and Validate tabs |
| `style.css` | Responsive styling |
| `app.js` | Form builder, JSON generation, and AJV validation logic |
| `ajv7.min.js` | Local copy of AJV v8.17.1 (JSON Schema draft-07 validator) |

## Dependencies

- A modern browser (Chrome, Firefox, Safari, Edge).
- No Node.js, npm, or build tools required.
- The AJV library is bundled locally — no CDN or network dependency at runtime.
