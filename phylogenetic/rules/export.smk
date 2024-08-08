"""
This part of the workflow collects the phylogenetic tree and annotations to
export a Nextstrain dataset.

See Augur's usage docs for these commands for more details.
"""

rule export:
    """Exporting data files for auspice"""
    input:
        tree = "results/tree.nwk",
        metadata = "data/metadata.tsv",
        branch_lengths = "results/branch_lengths.json",
        nt_muts = "results/nt_muts.json",
        aa_muts = "results/aa_muts.json",
        colors = config["files"]["colors"],
        auspice_config = config["files"]["auspice_config"],
        description = config["files"]["description"]
    output:
        auspice_json = "auspice/rabies.json"
    log:
        "logs/export.txt",
    benchmark:
        "benchmarks/export.txt"
    params:
        strain_id = config["strain_id_field"],
    shell:
        """
        augur export v2 \
            --tree {input.tree} \
            --metadata {input.metadata} \
            --metadata-id-columns {params.strain_id} \
            --node-data {input.branch_lengths} {input.nt_muts} {input.aa_muts} \
            --colors {input.colors} \
            --auspice-config {input.auspice_config} \
            --include-root-sequence-inline \
            --output {output.auspice_json} \
            --description {input.description} \
            2>&1 | tee {log}
        """
