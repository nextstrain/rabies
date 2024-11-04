"""
This part of the workflow handles fetching sequences and metadata from NCBI.

REQUIRED INPUTS:

    None

OUTPUTS:

    ndjson = data/ncbi.ndjson

There are two different approaches for fetching data from NCBI.
Choose the one that works best for the pathogen data and edit the workflow config
to provide the correct parameter.

1. Fetch with NCBI Datasets (https://www.ncbi.nlm.nih.gov/datasets/)
    - requires `ncbi_taxon_id` config
    - Directly returns NDJSON without custom parsing
    - Fastest option for large datasets (e.g. SARS-CoV-2)
    - Only returns metadata fields that are available through NCBI Datasets
    - Only works for viral genomes
"""

###########################################################################
####################### 1. Fetch from NCBI Datasets #######################
###########################################################################


rule fetch_ncbi_dataset_package:
    params:
        ncbi_taxon_id=config["ncbi_taxon_id"],
    output:
        dataset_package=temp("data/ncbi_dataset.zip"),
    # Allow retries in case of network errors
    retries: 5
    benchmark:
        "benchmarks/fetch_ncbi_dataset_package.txt"
    shell:
        """
        datasets download virus genome taxon {params.ncbi_taxon_id:q} \
            --no-progressbar \
            --filename {output.dataset_package}
        """

# Note: This rule is not part of the default workflow!
# It is intended to be used as a specific target for users to be able
# to inspect and explore the full raw metadata from NCBI Datasets.
rule dump_ncbi_dataset_report:
    input:
        dataset_package="data/ncbi_dataset.zip",
    output:
        ncbi_dataset_tsv="data/ncbi_dataset_report_raw.tsv",
    shell:
        """
        dataformat tsv virus-genome \
            --package {input.dataset_package} > {output.ncbi_dataset_tsv}
        """


rule extract_ncbi_dataset_sequences:
    input:
        dataset_package="data/ncbi_dataset.zip",
    output:
        ncbi_dataset_sequences=temp("data/ncbi_dataset_sequences.fasta"),
    benchmark:
        "benchmarks/extract_ncbi_dataset_sequences.txt"
    shell:
        """
        unzip -jp {input.dataset_package} \
            ncbi_dataset/data/genomic.fna > {output.ncbi_dataset_sequences}
        """


rule format_ncbi_dataset_report:
    input:
        dataset_package="data/ncbi_dataset.zip",
    output:
        ncbi_dataset_tsv=temp("data/ncbi_dataset_report.tsv"),
    params:
        ncbi_datasets_fields=",".join(config["ncbi_datasets_fields"]),
    benchmark:
        "benchmarks/format_ncbi_dataset_report.txt"
    shell:
        """
        dataformat tsv virus-genome \
            --package {input.dataset_package} \
            --fields {params.ncbi_datasets_fields:q} \
            --elide-header \
            | csvtk fix-quotes -Ht \
            | csvtk add-header -t -l -n {params.ncbi_datasets_fields:q} \
            | csvtk rename -t -f accession -n accession_version \
            | csvtk -t mutate -f accession_version -n accession -p "^(.+?)\." \
            | csvtk del-quotes -t \
            | tsv-select -H -f accession --rest last \
            > {output.ncbi_dataset_tsv}
        """

rule extract_ncbi_dataset_hosttaxid:
    input:
        ncbi_dataset_tsv="data/ncbi_dataset_report.tsv",
    output:
        ncbi_dataset_hosttaxid="data/ncbi_dataset_hosttaxid.tsv",
    log:
        "logs/extract_ncbi_dataset_hosttaxid.txt",
    benchmark:
        "benchmarks/extract_ncbi_dataset_hosttaxid.txt"
    shell:
        """
        tsv-select {input.ncbi_dataset_tsv} -H -f 'host\-tax\-id' | \
        tsv-filter --is-numeric 1 | \
        tsv-uniq \
        2> {log} > {output.ncbi_dataset_hosttaxid}
        """

rule get_ncbi_hosttax_info:
    input:
        ncbi_dataset_hosttaxid="data/ncbi_dataset_hosttaxid.tsv",
    output:
        ncbi_hosttax_info="data/hosttax_info.zip",
    # Allow retries in case of network errors
    retries: 5
    log:
        "logs/get_ncbi_hosttax_info.txt",
    benchmark:
        "benchmarks/get_ncbi_hosttax_info.txt"
    shell:
        """
        datasets download taxonomy taxon \
        --inputfile {input.ncbi_dataset_hosttaxid} \
        --filename {output.ncbi_hosttax_info} \
        2>&1 | tee {log}
        """

rule join_metadata_and_hostinfo:
    input:
        ncbi_hosttax_info="data/hosttax_info.zip",
        ncbi_dataset_tsv="data/ncbi_dataset_report.tsv",
    output:
        metadata = "data/metadata_with_taxinfo.tsv",
    log:
        "logs/join_metadata_and_hostinfo.txt",
    benchmark:
        "benchmarks/join_metadata_and_hostinfo.txt"
    params:
        ncbi_hosttax_columns = "Query,'Group\ name','Curator\ common\ name','Family\ name','Genus\ name'"
    shell:
        """
        unzip -p {input.ncbi_hosttax_info} ncbi_dataset/data/taxonomy_summary.tsv \
        | tsv-filter -H --not-blank Query \
        | tsv-select -H -f {params.ncbi_hosttax_columns} \
        | tsv-join -H \
        --filter-file - \
        --key-fields Query \
        --data-fields 'host\-tax\-id' \
        --append-fields '*' \
        --write-all ? \
        {input.ncbi_dataset_tsv} \
        2> {log} > {output.metadata}
        """

# Technically you can bypass this step and directly provide FASTA and TSV files
# as input files for the curate pipeline.
# We do the formatting here to have a uniform NDJSON file format for the raw
# data that we host on data.nextstrain.org
rule format_ncbi_datasets_ndjson:
    input:
        ncbi_dataset_sequences="data/ncbi_dataset_sequences.fasta",
        ncbi_dataset_tsv="data/metadata_with_taxinfo.tsv",
    output:
        ndjson="data/ncbi.ndjson",
    log:
        "logs/format_ncbi_datasets_ndjson.txt",
    benchmark:
        "benchmarks/format_ncbi_datasets_ndjson.txt"
    shell:
        """
        augur curate passthru \
            --metadata {input.ncbi_dataset_tsv} \
            --fasta {input.ncbi_dataset_sequences} \
            --seq-id-column accession_version \
            --seq-field sequence \
            --unmatched-reporting warn \
            --duplicate-reporting warn \
            2> {log} > {output.ndjson}
        """
