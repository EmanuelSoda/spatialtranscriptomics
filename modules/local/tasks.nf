import groovy.json.JsonSlurper

/*
 * Download mitochondrial genes list file
 */
 process MITO_LOAD {

    label "python_process_low"

    input:
    val sample_id
    val outdir

    output:
    tuple val(sample_id), env(fname)

    script:
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    mitoUrl="ftp://ftp.broadinstitute.org/distribution/metabolic/papers/Pagliarini/MitoCarta2.0/${sample_info.species}.MitoCarta2.0.txt"

    fname=${outdir}/`basename "\${mitoUrl}"`
    echo saving to: \$fname

    [ ! -d ${outdir} ] && mkdir ${outdir}

    if [ ! -f \$fname ]
    then
        wget --quiet \${mitoUrl} --output-document=\$fname
    fi
    """
}


//
// Read ST 10x visium and SC 10x data with Scanpy and save to `anndata` file
//
process READ_ST_AND_SC_SCANPY {

    label "python_process_low"

    input:
    tuple val(sample_id), file(state)
    val(outdir)

    output:
    tuple val(sample_id), file("*.st_adata_raw.h5ad"), emit: st_anndata
    tuple val(sample_id), file("*.sc_adata_raw.h5ad"), emit: sc_anndata
    tuple val(sample_id), file("*.st_*.npz"), emit: st_counts
    tuple val(sample_id), file("*.sc_*.npz"), emit: sc_counts

    script:
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id)
    sample_info = new JsonSlurper().parse(new File(fileName))
    """
    script_read_st_data.py \
        --outsPath=${sample_info.st_data_dir} \
        --saveFile=${sample_id}.st_adata_raw.h5ad \
        --npCountsOutputName=${sample_id}.st_adata_counts_in_tissue.npz \
        --countsFile=${sample_id}.raw_feature_bc_matrix.h5 \
        --minCounts=${params.STload_minCounts} \
        --minCells=${params.STload_minCells}

    script_read_sc_data.py \
        --outsPath=${sample_info.sc_data_dir} \
        --saveFile=${sample_id}.sc_adata_raw.h5ad \
        --npCountsOutputName=${sample_id}.sc_adata_counts.npz \
        --minCounts=${params.SCload_minCounts} \
        --minCells=${params.SCload_minCells} \
        --minGenes=${params.SCload_minGenes} \
    """
}


/*
 * Calculate ST and SC sum factors
 */
 process ST_CALCULATE_SUM_FACTORS {

    label "r_process"
    cpus 2
    memory '8.GB'

    input:
    tuple val(sample_id), file(state)
    val outdir

    output:
    tuple val(sample_id), env(outpath)

    """
    #!/bin/bash

    dname=${outdir}/${sample_id}

    Rscript $projectDir/bin/calculateSumFactors.R --filePath=\${dname}/ --npCountsOutputName=st_adata_counts_in_tissue.npz --npFactorsOutputName=st_adata_counts_in_tissue_factors.npz
    Rscript $projectDir/bin/calculateSumFactors.R --filePath=\${dname}/ --npCountsOutputName=sc_adata_counts.npz --npFactorsOutputName=sc_adata_counts_factors.npz

    if [[ -s \${dname}/st_adata_counts_in_tissue_factors.npz ]] && \
      [[ -s \${dname}/sc_adata_counts_factors.npz ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * ST data preprocessing
 */
 process ST_PREPROCESS {

    label "python_process"
    cpus 2
    memory '4.GB'

    input:
    tuple val(sample_id), file(state)
    val outdir

    output:
    tuple val(sample_id), env(outpath)

    script:
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    dname=${outdir}/${sample_id}

    mitoFile=${outdir}/${sample_info.species}.MitoCarta2.0.txt

    python $projectDir/bin/stPreprocess.py --filePath=\${dname}/ --npFactorsOutputName=st_adata_counts_in_tissue_factors.npz --rawAdata=st_adata_raw.h5ad --mitoFile=\$mitoFile --pltFigSize=$params.STpreprocess_pltFigSize --minCounts=$params.STpreprocess_minCounts --minGenes=$params.STpreprocess_minGenes --minCells=$params.STpreprocess_minCells --histplotQCmaxTotalCounts=$params.STpreprocess_histplotQCmaxTotalCounts --histplotQCminGeneCounts=$params.STpreprocess_histplotQCminGeneCounts --histplotQCbins=$params.STpreprocess_histplotQCbins

    if [[ -s \${dname}/st_adata_norm.h5ad ]] && \
      [[ -s \${dname}/st_adata_X.npz ]] && \
      [[ -s \${dname}/st_adata.var.csv ]] && \
      [[ -s \${dname}/st_adata.obs.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * SC data preprocessing
 */
 process SC_PREPROCESS {

    label "python_process"
    cpus 2
    memory '4.GB'

    input:
    tuple val(sample_id), file(state)
    val outdir

    output:
    tuple val(sample_id), env(outpath)

    script:
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    dname=${outdir}/${sample_id}

    mitoFile=${outdir}/${sample_info.species}.MitoCarta2.0.txt

    python $projectDir/bin/scPreprocess.py --filePath=\${dname}/ --npFactorsOutputName=sc_adata_counts_factors.npz --rawAdata=sc_adata_raw.h5ad --mitoFile=\$mitoFile --pltFigSize=$params.SCpreprocess_pltFigSize --minCounts=$params.SCpreprocess_minCounts --minGenes=$params.SCpreprocess_minGenes --minCells=$params.SCpreprocess_minCells --histplotQCmaxTotalCounts=$params.SCpreprocess_histplotQCmaxTotalCounts --histplotQCminGeneCounts=$params.SCpreprocess_histplotQCminGeneCounts --histplotQCbins=$params.SCpreprocess_histplotQCbins

    if [[ -s \${dname}/sc_adata_norm.h5ad ]] && \
      [[ -s \${dname}/sc_adata_X.npz ]] && \
      [[ -s \${dname}/sc_adata.var.csv ]] && \
      [[ -s \${dname}/sc_adata.obs.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}












/*
 * ST data deconvolution with STdeconvolve
 */
 process DECONVOLUTION_WITH_STDECONVOLVE {

    label "r_process"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    Rscript $projectDir/bin/characterization_STdeconvolve.R --filePath=\${dname}/ --outsPath=${sample_info.st_data_dir} --mtxGeneColumn=$params.STdeconvolve_mtxGeneColumn --countsFactor=$params.STdeconvolve_countsFactor --corpusRemoveAbove=$params.STdeconvolve_corpusRemoveAbove --corpusRemoveBelow=$params.STdeconvolve_corpusRemoveBelow --LDAminTopics=$params.STdeconvolve_LDAminTopics --LDAmaxTopics=$params.STdeconvolve_LDAmaxTopics --STdeconvolveScatterpiesSize=$params.STdeconvolve_ScatterpiesSize --STdeconvolveFeaturesSizeFactor=$params.STdeconvolve_FeaturesSizeFactor

    if [[ -s \${dname}/STdeconvolve_prop_norm.csv ]] && \
      [[ -s \${dname}/STdeconvolve_beta_norm.csv ]] && \
      [[ -s \${dname}/STdeconvolve_sc_cluster_ids.csv ]] && \
      [[ -s \${dname}/STdeconvolve_sc_pca.csv ]] && \
      [[ -s \${dname}/STdeconvolve_sc_pca_feature_loadings.csv ]] && \
      [[ -s \${dname}/STdeconvolve_sc_cluster_markers.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * ST data deconvolution with SPOTlight
 */
 process DECONVOLUTION_WITH_SPOTLIGHT {

    label "r_process"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    Rscript $projectDir/bin/characterization_SPOTlight.R --filePath=\${dname}/ --outsPath=${sample_info.st_data_dir} --mtxGeneColumn=$params.SPOTlight_mtxGeneColumn --countsFactor=$params.SPOTlight_countsFactor --clusterResolution=$params.SPOTlight_clusterResolution --numberHVG=$params.SPOTlight_numberHVG --numberCellsPerCelltype=$params.SPOTlight_numberCellsPerCelltype --SPOTlightScatterpiesSize=$params.SPOTlight_ScatterpiesSize

    if [[ -s \${dname}/SPOTlight_prop_norm.csv ]] && \
      [[ -s \${dname}/SPOTlight_beta_norm.csv ]] && \
      [[ -s \${dname}/SPOTlight_sc_cluster_ids.csv ]] && \
      [[ -s \${dname}/SPOTlight_sc_pca.csv ]] && \
      [[ -s \${dname}/SPOTlight_sc_pca_feature_loadings.csv ]] && \
      [[ -s \${dname}/SPOTlight_sc_cluster_markers.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * Resolution enhancement and spatial clustering with BayesSpace
 */
 process CLUSTERING_WITH_BAYESSPACE {

    label "r_process"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    Rscript $projectDir/bin/characterization_BayesSpace.R --filePath=\${dname}/ --numberHVG=$params.BayesSpace_numberHVG --numberPCs=$params.BayesSpace_numberPCs --minClusters=$params.BayesSpace_minClusters --maxClusters=$params.BayesSpace_maxClusters --optimalQ=$params.BayesSpace_optimalQ --STplatform=$params.BayesSpace_STplatform

    if [[ -s \${dname}/bayes_spot_cluster.csv ]] && \
      [[ -s \${dname}/bayes_subspot_cluster_and_coord.csv ]] && \
      [[ -s \${dname}/bayes_enhanced_markers.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * SpatialDE
 */
 process ST_SPATIALDE {

    label "python_process"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    python $projectDir/bin/stSpatialDE.py --filePath=\${dname}/ --numberOfColumns=$params.SpatialDE_numberOfColumns

    if [[ -s \${dname}/stSpatialDE.csv ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}
















/*
 * Clustering etc.
 */
 process ST_CLUSTERING {

    label "python_process"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    python $projectDir/bin/stClusteringWorkflow.py --filePath=\${dname}/ --resolution=$params.Clustering_resolution

    if [[ -s \${dname}/st_adata_processed.h5ad ]] && \
      [[ -s \${dname}/sc_adata_processed.h5ad ]]
    then
      echo "completed" > "output.out" && outpath=`pwd`/output.out
    else
      echo ERROR: Output files missing. >&2
      exit 2
    fi
    """
}


/*
 * Report
 */
 process ALL_REPORT {

    label "python_process_low"

    input:
    val sample_state
    val outdir

    output:
    tuple env(sample_id), env(outpath)

    script:
    def sample_id_gr = sample_state[0]
    def fileName = String.format("%s/sample_%s.json", outdir, sample_id_gr)
    sample_info = new JsonSlurper().parse(new File(fileName))

    """
    #!/bin/bash

    sample_id=${sample_id_gr}

    dname=${outdir}/\${sample_id}

    echo \${dname}/
    echo "completed" > "output.out" && outpath=`pwd`/output.out
    """
}

