/* Generated by Xtext 2.17.0 and then modified to support specific targets. */

/*************
 * Copyright (c) 2019-2020, The University of California at Berkeley.

 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:

 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.

 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.

 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ***************/
package org.lflang.generator

import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.lflang.Target
import org.lflang.lf.TargetDecl

/**
 * Generates code from your model files on save.
 * 
 * See https://www.eclipse.org/Xtext/documentation/303_runtime_concepts.html#code-generation
 */
class LFGenerator extends AbstractGenerator {

    // Indicator of whether generator errors occurred.
    protected var generatorErrorsOccurred = false

    override void doGenerate(Resource resource, IFileSystemAccess2 fsa,
        IGeneratorContext context) {
        // Determine which target is desired.
        var GeneratorBase generator

        val t = Target.forName(
            resource.allContents.toIterable.filter(TargetDecl).head.name)
            
        switch (t) {
            case C: {
                generator = new CGenerator()
            }
            case CCPP: {
                generator = new CCppGenerator()
            }
            case CPP: {
                generator = new CppGenerator()
            }
            case TS: {
                generator = new TypeScriptGenerator()
            }
            case Python: {
                generator = new PythonGenerator()
            }
        }
        
        generator?.doGenerate(resource, fsa, context)
        generatorErrorsOccurred = generator?.errorsOccurred()
    }

    /**
     * Return true if errors occurred in the last call to doGenerate().
     * @return True if errors occurred.
     */
    def errorsOccurred() {
        return generatorErrorsOccurred;
    }

}
