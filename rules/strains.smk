
rule Dstrain:
    input:
        ANI="tables/dist_strains.tsv",
        ani_dir='mummer/ANI',
        subsets_dir="mummer/subsets",
        delta_dir="mummer/delta"
    output:
        "mummer/delta.tar.gz"
    shell:
        " tar -czf {input.delta_dir}.tar.gz {input.delta_dir} ;"
        "rm -rf {input.subsets_dir} {input.delta_dir} {input.ani_dir}"


localrules: species_subsets
rule species_subsets:
    input:
        cluster_file=rules.cluster_mash.output.cluster_file,
    output:
        subsets_dir= temp(directory("mummer/subsets"))
    run:
        import pandas as pd
        labels= pd.read_csv(input[0],sep='\t',index_col=0).Species


        os.makedirs(output.subsets_dir)

        for species in labels.unique():

            genomes_of_cluster= labels.index[labels==species].values
            if len(genomes_of_cluster)>1:

                with open(f"{output.subsets_dir}/{species}.txt","w") as f:

                    f.write(''.join([g+'.fasta\n' for g in genomes_of_cluster ]))



def estimate_time_mummer(input,threads):
    "retur time in minutes"

    N= len(open(input.genome_list).read().split())

    time_per_mummer_call = 10/60

    return int(N**2/2*time_per_mummer_call + N/2)//threads + 5

localrules: get_deltadir,decompress_delta,Dstrain
rule get_deltadir:
    output:
        directory("mummer/delta")
    run:
        os.makedirs(output[0])

rule decompress_delta:
    input:
        "mummer/delta.tar.gz"
    output:
        directory("mummer/delta")
    shell:
        "tar -xzf {input}"
ruleorder: decompress_delta>get_deltadir


rule merge_mummer_ani:
    input:
        lambda wc: expand("mummer/ANI/{species}.tsv",species=get_species(wc))
    output:
        "tables/dist_strains.tsv"
    run:
        import pandas as pd
        Mummer={}
        for file in input:
            Mummer[io.simplify_path(file)]= pd.read_csv(file,index_col=[0,1],sep='\t')

        M= pd.concat(Mummer,axis=0)
        M['Species']=M.index.get_level_values(0)
        M.index= M.index.droplevel(0)
        M.to_csv(output[0],sep='\t')

        #sns.jointplot('ANI','Coverage',data=M.query('ANI>0.98'),kind='hex',gridsize=100,vmax=200)




rule run_mummer:
    input:
        genome_list="mummer/subsets/{species}.txt",
        genome_folder= genome_folder,
        genome_stats="tables/genome_stats.tsv",
        delta_dir="mummer/delta"
    output:
        temp("mummer/ANI/{species}.tsv")
    threads:
        config['threads']
    conda:
        "../envs/mummer.yaml"
    resources:
        time= lambda wc, input, threads: estimate_time_mummer(input,threads),
        mem=1
    log:
        "logs/mummer/workflows/{species}.txt"
    params:
        path= os.path.dirname(workflow.snakefile)
    shell:
        "snakemake -s {params.path}/rules/mummer.smk "
        "--config genome_list='{input.genome_list}' "
        " genome_folder='{input.genome_folder}' "
        " species={wildcards.species} "
        " genome_stats={input.genome_stats} "
        " --rerun-incomplete "
        "-j {threads} --nolock 2> {log}"