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

The app is a static site — no build step or package install required.
Just run the included launcher script (Python 3 only dependency):

```bash
python params_app/serve.py
```

This serves from the repository root, prints the full URL, and opens it in your browser.
An optional port argument is supported: `python params_app/serve.py 9000`.

## Files

| File | Description |
|------|-------------|
| `index.html` | App shell with Editor and Validate tabs |
| `style.css` | Responsive styling |
| `app.js` | Form builder, JSON generation, and AJV validation logic |
| `ajv7.min.js` | Local copy of AJV v8.17.1 (JSON Schema draft-07 validator) |
| `serve.py` | Cross-platform launcher (starts server, opens browser) |

## Dependencies

- A modern browser (Chrome, Firefox, Safari, Edge).
- No Node.js, npm, or build tools required.
- The AJV library is bundled locally — no CDN or network dependency at runtime.
