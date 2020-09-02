/* Generator for the Python target. */

/*************
Copyright (c) 2019, The University of California at Berkeley.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************/

package org.icyphy.generator

import java.io.File
import java.io.FileOutputStream
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext

import static extension org.icyphy.ASTUtils.*
import org.icyphy.linguaFranca.ReactorDecl
import org.icyphy.linguaFranca.Reaction
import java.util.HashMap
import org.icyphy.linguaFranca.Instantiation
import java.util.HashSet
import org.icyphy.linguaFranca.Action
import org.icyphy.linguaFranca.TriggerRef
import org.icyphy.linguaFranca.VarRef
import org.icyphy.linguaFranca.Port
import org.icyphy.linguaFranca.Input
import org.icyphy.linguaFranca.Output
import org.icyphy.linguaFranca.Reactor
import org.icyphy.linguaFranca.StateVar
import org.icyphy.linguaFranca.Parameter

/** 
 * Generator for Python target. This class generates Python code defining each reactor
 * class given in the input .lf file and imported .lf files.
 * 
 * Each class will contain all the reaction functions defined by the user in order, with the necessary ports/actions given as parameters.
 * Moreover, each class will contain all state variables in native Python format.
 * 
 * A backend is also generated using the CGenrator that interacts with the C code library (see CGenerator.xtend).
 * The backend is responsible for passing arguments to the Python reactor functions.
 *
 * @author{Soroush Bateni <soroush@utdallas.edu>}
 */
class PythonGenerator extends CGenerator {
	
	// Set of acceptable import targets includes only C.
    val acceptableTargetSet = newLinkedHashSet('Python')
	
	new () {
        super()
        // set defaults
        this.targetCompiler = "python3"
        this.targetCompilerFlags = "-m pip install ."// -Wall -Wconversion"
    }
	
    /** 
    * Template struct for ports with primitive types and
    * statically allocated arrays in Lingua Franca.
    * This template is defined as
    *     template <class T>
    *     struct template_input_output_port_struct {
    *         T value;
    *         bool is_present;
    *         int num_destinations;
    *     };
    *
    * @see xtext/org.icyphy.linguafranca/src/lib/CCpp/ccpptarget.h
    */
	val generic_port_type =  "generic_port_instance_struct*"

    /** 
    * Special template struct for ports with dynamically allocated
    * array types (a.k.a. token types) in Lingua Franca.
    * This template is defined as
    *     template <class T>
    *     struct template_input_output_port_struct {
    *         T value;
    *         bool is_present;
    *         int num_destinations;
    *         token_t* token;
    *         int length;
    *     };
    *
    * @see xtext/org.icyphy.linguafranca/src/lib/CCpp/ccpptarget.h
    */
	val generic_port_type_with_token = "generic_instance_with_token_struct*"
    
   ////////////////////////////////////////////
    //// Public methods
    
    
    ////////////////////////////////////////////
    //// Protected methods
    
    /**
     * Generate parameters for a reaction function
     * @param decl Reactor declaration
     * @param reaction The reaction to be used to generate parameters for
     */
    def generatePythonReactionParameters(ReactorDecl decl, Reaction reaction)
    {
        var StringBuilder parameters = new StringBuilder();
        val reactor = decl.toDefinition
        
        for (TriggerRef trigger : reaction.triggers ?:emptyList)
        {
            if (trigger instanceof VarRef)
            {
                if (trigger.variable instanceof Port)
                {  
                    if(trigger.variable instanceof Input)
                    {
                        parameters.append(''', «trigger.variable.name», «trigger.variable.name»_width''')
                    } else {
                        // FIXME: not using proper "."
                        parameters.append(''', «trigger.container.name»_«trigger.variable.name»''')
                    }
                        
                }
                else if (trigger.variable instanceof Action)
                {
                    // TODO: handle actions
                }
            }
        }
        if (reaction.triggers === null || reaction.triggers.size === 0)
        {
             for (input : reactor.inputs ?:emptyList) {
                parameters.append(''', «input.name», «input.name»_width''')
            }
        }
        for (src : reaction.sources ?:emptyList)
        {
                parameters.append(", " + src.variable.name)
        }
        for (effect : reaction.effects ?:emptyList)
        {
            if(effect.variable instanceof Input)
            {
                // FIXME: not using proper "."
                parameters.append(''', «effect.container.name»_«effect.variable.name»''')  
            }
            else{
                parameters.append(", " + effect.variable.name)                
            }
        }
        
        return parameters
        
      }
    
    /**
     * Handle initialization for state variable
     * @param state a state variable
     */
    def String getTargetInitializer(StateVar state) {
        '''«FOR init : state.initializerList SEPARATOR ", "»«init»«ENDFOR»'''
    }
    
    /**
     * Handle initialization for parameters
     * @param state a state variable
     */
    def String getTargetInitializer(Parameter par) {
        '''«FOR init : par.initializerList SEPARATOR ", "»«init»«ENDFOR»'''
    }
    
    /**
     * Generate a Python class for a given reactor
     * @param decl The reactor class
     */
    def generatePythonReactorClass(ReactorDecl decl)  '''
        «val reactor = decl.toDefinition»
        «FOR stateVar : reactor.allStateVars»
            «'    '»«stateVar.name»:«stateVar.targetType» = «stateVar.targetInitializer»
        «ENDFOR»
        
        «FOR param : reactor.allParameters»
            «'    '»«param.name»:«param.targetType» = «param.targetInitializer»
        «ENDFOR»
        
        «var reactionIndex = 0»
        «FOR reaction : reactor.allReactions»
               def «pythonReactionFunctionName(reactionIndex)»(self «generatePythonReactionParameters(reactor, reaction)»):
                   «reaction.code.toText»
                   return 0
           «{reactionIndex = reactionIndex+1; ""}»
        «ENDFOR»
        '''
        
    /**
     * Generate and instantiate all Python classes
     * @param decl The reactor's declaration
     */
    def generateAndInstantiatePythonReactorClass(ReactorDecl decl) '''
        «var className = ""»
        «IF decl instanceof Reactor»
            «{className = decl.name; ""}»
        «ELSE»
            «{className = decl.toDefinition.name; ""}»    
        «ENDIF»
        
        class _«className»:
        
        «generatePythonReactorClass(decl)»
                    
        «className» = _«className»()    
    '''
    
    /**
     * Generate the Python code constructed from reactor classes and user-written classes.
     * @return the code body 
     */
    def generatePythonCode() '''
       import LinguaFranca«filename»
       import sys
       
       # Function aliases
       start = LinguaFranca«filename».start
       SET = LinguaFranca«filename».SET
       
       «FOR reactor : reactors BEFORE '# Reactor classes\n' AFTER '\n'»
           «FOR d : this.instantiationGraph.getDeclarations(reactor)»
            «IF !reactor.allReactions.isEmpty»
                «d.generateAndInstantiatePythonReactorClass»
           «ENDIF»
           «ENDFOR»
       «ENDFOR»
       
       «IF !this.mainDef.reactorClass.toDefinition.allReactions.isEmpty»
           # The main reactor class
           «IF this.mainDef !== null»
               «mainDef.reactorClass.generateAndInstantiatePythonReactorClass»
           «ENDIF»
       «ENDIF»
       
       # The main function
       def main():
           start()
       
       # As is customary in Python programs, the main() function
       # should only be executed if the main module is active.
       if __name__=="__main__":
           main()
       '''
    
    /**
     * Generate the setup.py required to compile and install the module.
     * Currently, the package name is based on filename which does not support sharing the setup.py for multiple .lf files.
     * TODO: use an alternative package name (possibly based on folder name)
     */
    def generatePythonSetupFile() '''
    from setuptools import setup, Extension
    
    linguafranca«filename»module = Extension("LinguaFranca«filename»", ["«filename».c"])
    
    setup(name="LinguaFranca«filename»", version="1.0",
            ext_modules = [linguafranca«filename»module] )
    '''
    
    /**
     * Generate the necessary Python files
     * @param fsa The file system access (used to write the result).
     * 
     */
    def generatePythonFiles(IFileSystemAccess2 fsa)
    {
        var srcGenPath = getSrcGenPath()
        
        var file = new File(srcGenPath + File.separator + filename + ".py")
        if (file.exists) {
            file.delete
        }
        // Create the necessary directories
        if (!file.getParentFile().exists())
            file.getParentFile().mkdirs();
        writeSourceCodeToFile(generatePythonCode.toString.bytes, srcGenPath + File.separator + filename + ".py")
        
        // Handle Python setup
        file = new File(srcGenPath + File.separator + "setup.py")
        if (file.exists) {
            // Append
            file.delete
        }
            
        // Create the setup file
        writeSourceCodeToFile(generatePythonSetupFile.toString.bytes, srcGenPath + File.separator + "setup.py")        
        
    }
    
    /**
     * Return the necessary command to compile and install the current module
     */
     def pythonCompileCommand() {
         
         var compileCommand = newArrayList
         compileCommand.add("python3 -m pip install .")
         
         return compileCommand
     
    }
    
    /**
     * Execute the command that compiles and installs the current Python module
     */
    def pythonCompileCode()
    {
        executeCommand(pythonCompileCommand, getSrcGenPath)
    }
    
    /**
     * Returns the desired source gen. path
     */
    override getSrcGenPath() {
          directory + File.separator + "src-gen" + File.separator + filename
    }
     
    /**
     * Returns the desired output path
     */
    override getBinGenPath() {
          directory + File.separator + "src-gen" + File.separator + filename
    }
    
    /**
     * Python always uses heap memory for ports 
     */
    override getStackPortMember(String portName, String member){
         portName.getHeapPortMember(member)
     }
    
    /**
     * Invoke pip on the generated code.
     */
    override compileCode() {
        // If there is more than one federate, compile each one.
        //var fileToCompile = "" // base file name.
        /*for (federate : federates) {
            // Empty string means no federates were defined, so we only
            // compile one file.
            if (!federate.isSingleton) {
                fileToCompile = filename + '_' + federate.name
            }*/
        //executeCommand(pythonCompileCommand, directory + File.separator + "src-gen")
        //}
        // Also compile the RTI files if there is more than one federate.
        /*if (federates.length > 1) {
            compileRTI()
        }*/
        // TODO: add support for compiling federates
        return 0
    }
    
    /**
     * Generate the aliases for inputs, outputs, and struct type definitions for 
     * actions of the specified reactor in the specified federate.
     * @param reactor The parsed reactor data structure.
     * @param federate A federate name, or null to unconditionally generate.
     */
    override generateAuxiliaryStructs(
        ReactorDecl decl, FederateInstance federate
    ) {
        val reactor = decl.toDefinition
        // First, handle inputs.
        for (input : reactor.allInputs) {
            if (input.inferredType.isTokenType) {
                pr(input, code, '''
                    typedef «generic_port_type_with_token» «variableStructType(input, reactor)»;
                ''')
            }
            else
            {
                pr(input, code, '''
                   typedef «generic_port_type» «variableStructType(input, reactor)»;
                ''')                
            }
            
        }
        // Next, handle outputs.
        for (output : reactor.allOutputs) {
            if (output.inferredType.isTokenType) {
                 pr(output, code, '''
                    typedef «generic_port_type_with_token» «variableStructType(output, reactor)»;
                 ''')
            }
            else
            {
                pr(output, code, '''
                    typedef «generic_port_type» «variableStructType(output, reactor)»;
                ''')
            }
        }
        // Finally, handle actions.
        // The very first item on this struct needs to be
        // a trigger_t* because the struct will be cast to (trigger_t*)
        // by the schedule() functions to get to the trigger.
        for (action : reactor.allActions) {
            pr(action, code, '''
                typedef struct {
                    trigger_t* trigger;
                    «action.valueDeclaration»
                    bool is_present;
                    bool has_value;
                    token_t* token;
                } «variableStructType(action, reactor)»;
            ''')
        }
    }
    
    /** Return a set of targets that are acceptable to this generator.
     *  Imported files that are Lingua Franca files must specify targets
     *  in this set or an error message will be reported and the import
     *  will be ignored. The returned set contains only "C".
     */
    override acceptableTargets() {
        acceptableTargetSet
    }
    
    /** Add necessary include files specific to the target language.
     *  Note. The core files always need to be (and will be) copied 
     *  uniformly across all target languages.
     */
    override includeTargetLanguageHeaders()
    {
        pr('''#define MODULE_NAME LinguaFranca«filename»''')    	
        pr('#include "pythontarget.h"')
    }
    
    /** Add necessary source files specific to the target language.  */
    override includeTargetLanguageSourceFiles()
    {
        if (targetThreads > 0) {
            // Set this as the default in the generated code,
            // but only if it has not been overridden on the command line.
            pr(startTimers, '''
                if (number_of_threads == 0) {
                   number_of_threads = «targetThreads»;
                }
            ''')
        }
        if (federates.length > 1) {
            pr("#include \"core/federate.c\"")
        }
    }

    /** Generate C code from the Lingua Franca model contained by the
     *  specified resource. This is the main entry point for code
     *  generation.
     *  @param resource The resource containing the source code.
     *  @param fsa The file system access (used to write the result).
     *  @param context FIXME: Undocumented argument. No idea what this is.
     */
    override void doGenerate(Resource resource, IFileSystemAccess2 fsa,
            IGeneratorContext context) {
                // Always use the non-threaded version
                targetThreads = 0
            	super.doGenerate(resource, fsa, context)
                generatePythonFiles(fsa)
                pythonCompileCode
            }
            
    
    /**
     * Copy Python specific target code to the src-gen directory
     */        
    override copyTargetFiles()
    {    	
        var srcGenPath = getSrcGenPath()
    	// Copy the required target language files into the target file system.
        // This will also overwrite previous versions.
        var targetFiles = newArrayList("pythontarget.h");
        for (file : targetFiles) {
            copyFileFromClassPath(
                "/" + "lib" + "/" + "Python" + "/" + file,
                srcGenPath + File.separator + file
            )
        }
        
        // Copy the C target header.
        // This will also overwrite previous versions.
        var cTargetFiles = newArrayList("ctarget.h");
        for (file : cTargetFiles) {
            copyFileFromClassPath(
                "/" + "lib" + "/" + "C" + "/" + file,
                srcGenPath + File.separator + file
            )
        }
    }
    
     /** Return the function name in Python
     *  @param reactor The reactor
     *  @param reactionIndex The reaction index.
     *  @return The function name for the reaction.
     */
    def pythonReactionFunctionName(int reactionIndex) {
          "reaction_function_" + reactionIndex
    }
    
        
    /** Generate a reaction function definition for a reactor.
     *  This function has a single argument that is a void* pointing to
     *  a struct that contains parameters, state variables, inputs (triggering or not),
     *  actions (triggering or produced), and outputs.
     *  @param reaction The reaction.
     *  @param reactor The reactor.
     *  @param reactionIndex The position of the reaction within the reactor. 
     */
    override generateReaction(Reaction reaction, ReactorDecl decl, int reactionIndex) {
        
        val reactor = decl.toDefinition
        // Contains "O" characters. The number of these characters depend on the number of inputs to the reaction
        val StringBuilder pyObjectDescriptor = new StringBuilder()

        // Define the "self" struct.
        var structType = selfStructType(decl)
        
        // Contains the actual comma separated list of inputs to the reaction of type generic_port_instance_struct or generic_port_instance_with_token_struct.
        // Each input must be cast to (PyObject *)
        val StringBuilder pyObjects = new StringBuilder()
        
        // Create a unique function name for each reaction.
        val functionName = reactionFunctionName(decl, reactionIndex)
        
        // Generate the function name in Python
        val pythonFunctionName = pythonReactionFunctionName(reactionIndex);
        
               
        // Next, add the triggers (input and actions; timers are not needed).
        // TODO: handle triggers
        for (TriggerRef trigger : reaction.triggers ?: emptyList) {
            if (trigger instanceof VarRef) {
                if (trigger.variable instanceof Port) {
                    generatePortVariablesToSendToPythonReaction(pyObjectDescriptor, pyObjects, trigger, decl)
                } else if (trigger.variable instanceof Action) {
                    // TODO: handle actions
                }
            }
        }
        if (reaction.triggers === null || reaction.triggers.size === 0) {
            // No triggers are given, which means react to any input.
            // Declare an argument for every input.
            // NOTE: this does not include contained outputs. 
            for (input : reactor.inputs) {
                generateInputVariablesToSendToPythonReaction(pyObjectDescriptor, pyObjects, input, decl)              
            }
        }
        
        // Next add non-triggering inputs.
        for (VarRef src : reaction.sources ?: emptyList) {
            if(src.variable instanceof Port)
            {
                generatePortVariablesToSendToPythonReaction(pyObjectDescriptor, pyObjects, src, decl)
            } else if (src.variable instanceof Action) {
                //TODO: handle actions
            }
        }
        
        // Finally handle effects
        if (reaction.effects !== null) {
            for (effect : reaction.effects) {
                if(effect.variable instanceof Action)
                {
                    // TODO: handle action
                } else {
                    if (effect.variable instanceof Output) {
                        generateOutputVariablesToSendToPythonReaction(pyObjectDescriptor, pyObjects, effect.variable as Output, decl)
                    } else if (effect.variable instanceof Input ) {
                        // It is the input of a contained reactor.
                        generateVariablesForSendingToContainedReactors(pyObjectDescriptor, pyObjects, effect.container, effect.variable as Input, decl)                
                    } else {
                        reportError(
                            reaction,
                            "In generateReaction(): " + effect.variable.name + " is neither an input nor an output."
                        )
                    }
                
                }
            }
        }

        pr('void ' + functionName + '(void* instance_args) {')
        indent()

        pr(structType + "* self = (" + structType + "*)instance_args;")
        // Code verbatim from 'reaction'
        prSourceLineNumber(reaction.code)
        pr('''invoke_python_function("__main__", "«reactor.name»", "«pythonFunctionName»", Py_BuildValue("(«pyObjectDescriptor»)" «pyObjects»));''')
        unindent()
        pr("}")
        
        // Now generate code for the deadline violation function, if there is one.
        if (reaction.deadline !== null) {
            // The following name has to match the choice in generateReactionInstances
            val deadlineFunctionName = decl.name.toLowerCase + '_deadline_function' + reactionIndex

            pr('void ' + deadlineFunctionName + '(void* instance_args) {')
            indent();
            //pr(reactionInitialization.toString)
            // Code verbatim from 'deadline'
            //prSourceLineNumber(reaction.deadline.code)
            //pr(reaction.deadline.code.toText)
            // TODO: Handle deadlines
            unindent()
            pr("}")
        }
    }
    
    
    /**
     * Generate a constructor for the specified reactor in the specified federate.
     * @param reactor The parsed reactor data structure.
     * @param federate A federate name, or null to unconditionally generate.
     * @param constructorCode Lines of code previously generated that need to
     *  go into the constructor.
     */
    override generateConstructor(
        ReactorDecl decl, FederateInstance federate, StringBuilder constructorCode
    ) {
        val structType = selfStructType(decl)
        val StringBuilder portsAndTriggers = new StringBuilder()
        
        val reactor = decl.toDefinition
  
                
        // Initialize actions in Python
        for (action : reactor.allActions) {
            // TODO
        }
        
        // Next handle inputs.
        for (input : reactor.allInputs) {
           if (input.isMultiport) {
               // TODO
           }
           else
           {
                pr(input, portsAndTriggers, '''
                    self->__«input.name» =  PyObject_GC_New(generic_port_instance_struct, &port_instance_t);
                ''')
           }
        }
        
        // Next handle outputs.
        for (output : reactor.allOutputs) {
            if (output.isMultiport) {
                // TODO
            } else {
                pr(output, portsAndTriggers, '''
                    self->__«output.name» =  PyObject_GC_New(generic_port_instance_struct, &port_instance_t);
                ''')
            }
        }
        
        // Handle outputs of contained reactors
        for (reaction : reactor.allReactions)
        {
            for (effect : reaction.effects ?:emptyList)
            {
                if(effect.variable instanceof Input)
                {
                    pr(effect.variable , portsAndTriggers, '''
                        self->__«effect.container.name».«effect.variable.name» =  PyObject_GC_New(generic_port_instance_struct, &port_instance_t);
                    ''')
                }
                else {
                    // Do nothing
                }
            }
        }
            
        pr('''
            «structType»* new_«reactor.name»() {
                «structType»* self = («structType»*)calloc(1, sizeof(«structType»));
                «constructorCode.toString»
                «portsAndTriggers.toString»
                return self;
            }
        ''')
    }

    /** Generate into the specified string builder the code to
     *  send local variables for ports to a Python reaction function
     *  from the "self" struct. The port may be an input of the
     *  reactor or an output of a contained reactor. The second
     *  argument provides, for each contained reactor, a place to
     *  write the declaration of the output of that reactor that
     *  is triggering reactions.
     *  @param builder The string builder into which to write the code.
     *  @param structs A map from reactor instantiations to a place to write
     *   struct fields.
     *  @param port The port.
     *  @param reactor The reactor.
     */
    private def generatePortVariablesToSendToPythonReaction(
        StringBuilder pyObjectDescriptor,
        StringBuilder pyObjects,
        VarRef port,
        ReactorDecl decl        
    )
    {
        if(port.variable instanceof Input)
        {
            generateInputVariablesToSendToPythonReaction(pyObjectDescriptor, pyObjects, port.variable as Input, decl)
        }
        else
        {
            pyObjectDescriptor.append("O")
            pyObjects.append(''', (PyObject *)self->__«port.container.name».«port.variable.name»''')
        }
    }
    
    /** Generate into the specified string builder the code to
     *  send local variables for output ports to a Python reaction function
     *  from the "self" struct.
     *  @param builder The string builder into which to write the code.
     *  @param structs A map from reactor instantiations to a place to write
     *   struct fields.
     *  @param output The output port.
     *  @param decl The reactor declaration.
     */
    private def generateOutputVariablesToSendToPythonReaction(
        StringBuilder pyObjectDescriptor,
        StringBuilder pyObjects,
        Output output,
        ReactorDecl decl        
    )
    {
         if (output.type === null) {
            reportError(output,
                "Output is required to have a type: " + output.name)
        } else {
            val outputStructType = variableStructType(output, decl)
            // Unfortunately, for the SET macros to work out-of-the-box for
            // multiports, we need an array of *pointers* to the output structs,
            // but what we have on the self struct is an array of output structs.
            // So we have to handle multiports specially here a construct that
            // array of pointers.
            if (!output.isMultiport) {
                pyObjectDescriptor.append("O")
                pyObjects.append(''', (PyObject *)self->__«output.name»''')
            } else {
                // Set the _width variable.                
                pyObjectDescriptor.append("O")
                pyObjects.append(''', (PyObject *)self->__«output.name»''')
                
                // TODO: handle multiports
                /*pr(builder, '''
                    «outputStructType»* «output.name»[«output.name»_width];
                    for(int i=0; i < «output.name»_width; i++) {
                         «output.name»[i] = &(self->__«output.name»[i]);
                    }
                ''')*/
                
                pyObjectDescriptor.append("i")
                pyObjects.append(''', self->__«output.name»__width''')
            }
        }
    }
    
    /** Generate into the specified string builder the code to
     *  pass local variables for sending data to an input
     *  of a contained reaction (e.g. for a deadline violation).
     *  @param builder The string builder.
     *  @param definition AST node defining the reactor within which this occurs
     *  @param input Input of the contained reactor.
     */
    private def generateVariablesForSendingToContainedReactors(
        StringBuilder pyObjectDescriptor,
        StringBuilder pyObjects,
        Instantiation definition,
        Input input,
        ReactorDecl decl        
    )
    {
        // TODO: handle multiports
        pyObjectDescriptor.append("O")
        pyObjects.append(''', (PyObject *)self->__«definition.name».«input.name»''')
    }
    
    /** Generate into the specified string builder the code to
     *  send local variables for input ports to a Python reaction function
     *  from the "self" struct.
     *  @param builder The string builder into which to write the code.
     *  @param structs A map from reactor instantiations to a place to write
     *   struct fields.
     *  @param input The input port.
     *  @param reactor The reactor.
     */
    private def generateInputVariablesToSendToPythonReaction(
        StringBuilder pyObjectDescriptor,
        StringBuilder pyObjects,
        Input input,
        ReactorDecl decl        
    )
    {        
        // Create the local variable whose name matches the input name.
        // If the input has not been declared mutable, then this is a pointer
        // to the upstream output. Otherwise, it is a copy of the upstream output,
        // which nevertheless points to the same token and value (hence, as done
        // below, we have to use writable_copy()). There are 8 cases,
        // depending on whether the input is mutable, whether it is a multiport,
        // and whether it is a token type.
        // Easy case first.
        if (!input.isMutable && !input.isMultiport) {
            // Non-mutable, non-multiport, primitive type.
            pyObjectDescriptor.append("O")
            pyObjects.append(''', (PyObject *)*self->__«input.name»''')
        } else if (input.isMutable && !input.isMultiport) {
            // Mutable, non-multiport, primitive type.
            pyObjectDescriptor.append("O")
            pyObjects.append(''', (PyObject *)*self->__«input.name»''')
        } else if (!input.isMutable && input.isMultiport) {
            // Non-mutable, multiport, primitive.
            // TODO: support multiports
        } else {
            // Mutable, multiport, primitive type
            // TODO: support multiports
        }
        // Set the _width variable for all cases. This will be -1
        // for a variable-width multiport, which is not currently supported.
        // It will be -2 if it is not multiport.
        pyObjectDescriptor.append("i")
        pyObjects.append(''', self->__«input.name»__width''')
    }
    
}