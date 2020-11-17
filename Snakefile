# Initially the shell commands do not do anything
# They simply echo the input filename into the expected output file
import itertools as it
import os

wildcard_constraints:
    algorithm='\w+'#,
#    params='^(?!.*raw$).*$'

algorithms = ['pathlinker']
pathlinker_params = ['k5', 'k10']
datasets = ['data1']
data_dir = 'input'
out_dir = 'output'

# Eventually we'd store these values in a config file
run_options = {}
run_options["augment"] = False
run_options["parameter-advise"] = False

# Determine which input files are needed based on the
# pathway reconstruction algorithm
def reconstruction_inputs(wildcards):
    if wildcards.algorithm == 'pathlinker':
        inputs = ['sources', 'targets', 'network']
    elif wildcards.algorithm == 'pcsf':
        inputs = ['nodes', 'network']
    # Not currently used, placeholder
    else:
        inputs = ['other']
    #return it.chain([f'--{type}' for type in inputs], [os.path.join(out_dir, f'{dataset}-{algorithm}-{type}.txt') for type in inputs])
    return expand(os.path.join(out_dir, '{{dataset}}-{{algorithm}}-{type}.txt'), type=inputs) 
    #return expand('--{type} ' + os.path.join(out_dir, '{{dataset}}-{{algorithm}}-{type}.txt'), type=inputs) 
    #return [os.path.join(out_dir, '{dataset}-{algorithm}-sources.txt'), os.path.join(out_dir, '{dataset}-{algorithm}-targets.txt'), os.path.join(out_dir, '{dataset}-{algorithm}-network.txt')]

# Choose the final input for reconstruct_pathways based on which options are being run
# Right now this is a static run_options dictionary but would eventually
# be done with the config file
def make_final_input(wildcards):
    # Right now this lets us do ppa or augmentation, but not both. 
    # An easy solution would be to make a seperate rule for doing both, but 
    # if we add more things to do after the fact that will get
    # out of control pretty quickly. Steps run in parallel won't have this problem, just ones
    # whose inputs depend on each other. 
    # Currently, this will not re-generate all of the individual pathways
    # when augmenting or advising
    if run_options["augment"]:
        final_input = expand('{out_dir}{sep}{dataset}-{algorithm}-{params}-pathway-augmented.txt', out_dir=out_dir, sep=os.sep, dataset=datasets, algorithm=algorithms, params=pathlinker_params)
    elif run_options["parameter-advise"]:
        #not a great name
        final_input = expand('{out_dir}{sep}{dataset}-{algorithm}-pathway-advised.txt', out_dir=out_dir, sep=os.sep, dataset=datasets, algorithm=algorithms)
    else:
        final_input = expand('{out_dir}{sep}{dataset}-{algorithm}-{params}-pathway.txt', out_dir=out_dir, sep=os.sep, dataset=datasets, algorithm=algorithms, params=pathlinker_params)
    return final_input

# A rule to define all the expected outputs from all pathway reconstruction
# algorithms run on all datasets for all arguments
rule reconstruct_pathways:
    # Look for a more elegant way to use the OS-specific separator
    # Probably do not want filenames to dictate which parameters to sweep over,
    # consider alternative implementations
    # input: expand('{out_dir}{sep}{dataset}-{algorithm}-{params}-pathway.txt', out_dir=out_dir, sep=os.sep, dataset=datasets, algorithm=algorithms, params=pathlinker_params)
    input: make_final_input 
    # Test only the prepare_input_pathlinker rule
    # If using os.path.join use it everywhere because having some / and some \
    # separators can cause the pattern matching to fail
    #input: os.path.join(out_dir, 'data1-pathlinker-network.txt')

# One rule per reconstruction method initially
# Universal input to PathLinker input
rule prepare_input_pathlinker:
    input:
        sources=os.path.join(data_dir, '{dataset}-sources.txt'),
        targets=os.path.join(data_dir, '{dataset}-targets.txt'),
        network=os.path.join(data_dir, '{dataset}-network.txt')
    # No need to use {algorithm} here instead of 'pathlinker' if this is a
    # PathLinker rule instead of a generic prepare input rule
    output:
        sources=os.path.join(out_dir, '{dataset}-{algorithm}-sources.txt'),
        targets=os.path.join(out_dir, '{dataset}-{algorithm}-targets.txt'),
        network=os.path.join(out_dir, '{dataset}-{algorithm}-network.txt')
    # run the preprocessing script for PathLinker
    # With Git Bash on Windows multiline strings are not executed properly
    # https://carpentries-incubator.github.io/workflows-snakemake/07-resources/index.html
    shell:
        '''
        echo {input.sources} >> {output.sources} && echo {input.targets} >> {output.targets} && echo {input.network} >> {output.network}
        '''

# Run PathLinker or other pathway reconstruction
rule reconstruct:
    input: reconstruction_inputs
#        sources=os.path.join(out_dir, '{dataset}-{algorithm}-sources.txt'),
#        targets=os.path.join(out_dir, '{dataset}-{algorithm}-targets.txt'),
#        network=os.path.join(out_dir, '{dataset}-{algorithm}-network.txt')
    output: os.path.join(out_dir, '{dataset}-{algorithm}-{params}-raw-pathway.txt')
    # run PathLinker
    shell: 'echo {input} && echo {input} >> {output} && echo Params: {wildcards.params} >> {output}'

# PathLinker output to universal output
rule parse_output_pathlinker:
    input: os.path.join(out_dir, '{dataset}-{algorithm}-{params}-raw-pathway.txt')
    output: os.path.join(out_dir, '{dataset}-{algorithm}-{params}-pathway.txt')
    # run the post-processing script for PathLinker
    shell: 'echo {input} >> {output}'

# Pathway Augmentation
rule augment_pathway:
    input: os.path.join(out_dir, '{dataset}-{algorithm}-{params}-pathway.txt')
    output: os.path.join(out_dir, '{dataset}-{algorithm}-{params}-pathway-augmented.txt')
    shell: 'echo {input} >> {output}'

# Pathway Parameter Advising
rule parameter_advise:
    input: expand('{out_dir}{sep}{dataset}-{algorithm}-{params}-pathway.txt', out_dir=out_dir, sep=os.sep, dataset=datasets, algorithm=algorithms, params=pathlinker_params)
    output: os.path.join(out_dir, '{dataset}-{algorithm}-pathway-advised.txt')
    shell: 'echo {input} >> {output}'

# Remove the output directory
rule clean:
    shell: f'rm -rf {out_dir}'