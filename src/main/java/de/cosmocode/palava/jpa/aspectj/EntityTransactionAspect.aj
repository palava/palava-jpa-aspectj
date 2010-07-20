/**
 * Copyright 2010 CosmoCode GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package de.cosmocode.palava.jpa.aspectj;

import javax.persistence.EntityManager;
import javax.persistence.EntityTransaction;
import javax.persistence.PersistenceException;

import org.aspectj.lang.annotation.SuppressAjWarnings;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.base.Preconditions;
import com.google.inject.Inject;
import com.google.inject.Provider;

import de.cosmocode.palava.core.aop.AbstractPalavaAspect;
import de.cosmocode.palava.jpa.Transactional;

public final aspect EntityTransactionAspect extends AbstractPalavaAspect issingleton() {

    private static final Logger LOG = LoggerFactory.getLogger(EntityTransactionAspect.class);

    private Provider<EntityManager> currentManager;
    
    @Inject
    public void setProvider(Provider<EntityManager> manager) {
        this.currentManager = Preconditions.checkNotNull(manager, "Manager");
    }
    
    pointcut transactional(): execution(@Transactional * *.*(..));

    @SuppressAjWarnings("adviceDidNotMatch")
    Object around(): transactional() {
        final EntityManager manager = currentManager.get();
        LOG.trace("Retrieved entitymanager {}", manager);
        final EntityTransaction tx = manager.getTransaction();
        LOG.trace("Using transaction {}", tx);
        final boolean localTx = !tx.isActive();
        
        if (localTx) {
            LOG.trace("Beginning automatic transaction");
            tx.begin();
        } else {
            LOG.trace("Transaction already active");
        }
        
        final Object returnValue;
        
        try {
            returnValue = proceed();
        } catch (RuntimeException e) {
            LOG.debug("Exception inside automatic transaction context; rolling back", e);
            tx.rollback();
            throw e;
        }
        
        if (localTx && tx.isActive()) {
            if (tx.getRollbackOnly()) {
                LOG.debug("Transaction was marked as rollback only. Rolling back...");
                tx.rollback();
            } else {
                try {
                    tx.commit();
                    LOG.trace("Committed automatic transaction");
                } catch (PersistenceException e) {
                    LOG.debug("Commit in automatic transaction context failed", e);
                    if (tx.isActive()) {
                        LOG.debug("Rolling back {}", tx);
                        tx.rollback();
                    } else {
                        LOG.debug("Can't roll back inactive transaction {}", tx);
                    }
                    throw e;
                }
            }
        } else {
            LOG.trace("Not committing non-local transaction {}", tx);
        }
        
        return returnValue;
    }
    
}
