//
// Spatial differential expression
//
process ST_SPATIAL_DE {

    // TODO: Add a better description
    // TODO: Update Conda directive when Quarto/Pandoc works on ARM64

    tag "${meta.id}"
    label 'process_medium'

    conda "env/st_spatial_de/environment.yml"
    container "docker.io/erikfas/spatialtranscriptomics"

    // Exit if running this module with -profile conda / -profile mamba on ARM64
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        architecture = System.getProperty("os.arch")
        if (architecture == "arm64" || architecture == "aarch64") {
            exit 1, "The ST_SPATIAL_DE module does not support Conda on ARM64. Please use Docker / Singularity / Podman instead."
        }
    }
    input:
    path(report)
    tuple val(meta), path(st_adata_norm, stageAs: "adata_norm.h5ad")

    output:
    tuple val(meta), path("*.csv")              , emit: degs
    tuple val(meta), path("st_spatial_de.html") , emit: html
    path("versions.yml")                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    quarto render ${report} \
        --output "st_spatial_de.html" \
        -P fileNameST:${st_adata_norm} \
        -P numberOfColumns:${params.st_spatial_de_ncols} \
        -P saveDEFileName:st_gde.csv \
        -P saveSpatialDEFileName:st_spatial_de.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        quarto: \$(quarto -v)
        leidenalg: \$(python -c "import leidenalg; print(leidenalg.version)")
        scanpy: \$(python -c "import scanpy; print(scanpy.__version__)")
        SpatialDE: \$(python -c "from importlib.metadata import version; print(version('SpatialDE'))")
    END_VERSIONS
    """
}
