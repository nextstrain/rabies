"""
This part of the workflow constructs the phylogenetic tree.

See Augur's usage docs for these commands for more details.
"""

rule tree:
    """Building tree"""
    input:
        alignment = "results/aligned.fasta"
    output:
        tree = "results/tree_raw.nwk"
    log:
        "logs/tree.txt",
    benchmark:
        "benchmarks/tree.txt"
    shell:
        """
        augur tree \
            --alignment {input.alignment} \
            --output {output.tree} \
            2>&1 | tee {log}
        """

rule refine:
    """
    Refining tree
      - add node information
    """
    input:
        tree = "results/tree_raw.nwk",
        alignment = "results/aligned.fasta",
        metadata = "data/metadata.tsv"
    output:
        tree = "results/tree.nwk",
        node_data = "results/branch_lengths.json"
    log:
        "logs/refine.txt",
    benchmark:
        "benchmarks/refine.txt"
    params:
        strain_id = config["strain_id_field"]
    shell:
        """
        augur refine \
            --tree {input.tree} \
            --alignment {input.alignment} \
            --metadata {input.metadata} \
            --metadata-id-columns {params.strain_id} \
            --output-tree {output.tree} \
            --output-node-data {output.node_data} \
            --root mid_point \
            2>&1 | tee {log}
        """
