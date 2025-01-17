package org.lflang.diagram.synthesis.action

import de.cau.cs.kieler.klighd.IAction
import de.cau.cs.kieler.klighd.internal.util.KlighdInternalProperties
import de.cau.cs.kieler.klighd.kgraph.KGraphElement
import de.cau.cs.kieler.klighd.kgraph.KNode
import org.lflang.lf.Reactor

/**
 * Abstract super class for diagram actions that provides some convince methods.
 * 
 * @author{Alexander Schulz-Rosengarten <als@informatik.uni-kiel.de>}
 */
abstract class AbstractAction implements IAction {
	
	def Object sourceElement(KGraphElement elem) {
		return elem.getProperty(KlighdInternalProperties.MODEL_ELEMEMT)
	}
	
	def boolean sourceIsReactor(KNode node) {
		return node.sourceElement() instanceof Reactor
	}
	
	def Reactor sourceAsReactor(KNode node) {
		if (node.sourceIsReactor()) {
			return node.sourceElement() as Reactor
		}
		return null
	}
}