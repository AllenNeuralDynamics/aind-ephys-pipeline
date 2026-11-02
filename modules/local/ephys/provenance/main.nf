// Provenance: record pipeline version, vendored repos + commits and effective parameters
process EPHYS_PROVENANCE {
    tag 'provenance'
    label 'process_cpu'

    input:
    val provenance_json

    output:
    path 'provenance.json', emit: provenance


    script:
    """
    #!/usr/bin/env bash
    set -e

    cat > provenance.json <<'PROVENANCE_EOF'
${groovy.json.JsonOutput.prettyPrint(provenance_json)}
PROVENANCE_EOF
    """

    stub:
    """
    cat > provenance.json <<'PROVENANCE_EOF'
${groovy.json.JsonOutput.prettyPrint(provenance_json)}
PROVENANCE_EOF
    """
}
