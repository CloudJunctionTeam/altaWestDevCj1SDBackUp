public without sharing class ConditionAdmissionEvaluator {
    // Exceptions Declaration
    public class InvalidParamException extends Exception {}
    public class InvalidObjectApiNameException extends Exception {}
    public class CustomMalformedQueryException extends Exception {}

    // Primitive Variables Declaration
    String objectApiName;
    String relationshipFieldName;

    // List or Set Declarations
    List<Id> listOfIds;
    List<Id> listOfRlaIds;
    List<sObject> recordsList;
    Set<String> conditionsSubjectsSet;
    

    // Map Declarations
    Map<Id, List<Conditions_Admission_Criterion__mdt>> mappingToCriteriaMap;
    Map<Id, Conditions_Admission_Mapping__mdt> mappingMap;
    Map<String, Task> mappingAndRecordTaskMap;


    // Begin Execution of invokable method for Condition Criteria Evaluation
    @InvocableMethod(label='Invoke Condition Evaluation' description='Pass List of Ids of records and Condition Evaluation')
    public static List<String> invokeConditionAdmissionEvaluator(List<Id> listOfIds) {
        
        // Class initialization and param checks
        ConditionAdmissionEvaluator evaluator = new ConditionAdmissionEvaluator();
        if(listOfIds == null || listOfIds.size() == 0) {
            throw new InvalidParamException('ConditionAdmissionEvaluator.invokeConditionAdmissionEvaluator invoked with null or empty list of parameters');
        }

        // Retrieve and validate object api name 
        evaluator.listOfIds = listOfIds;
        System.debug(listOfIds[0]);
        evaluator.objectApiName = String.valueOf(listOfIds[0].getsobjecttype());
        if(evaluator.objectApiName == null || evaluator.objectApiName.length() == 0) {
            throw new InvalidObjectApiNameException('ConditionAdmissionEvaluator.invokeConditionAdmissionEvaluator: Unable to parse Object Api Name for which conditions have to be evaluated');
        }

        // Create Condition Admission Criteria Map and return comma separated list of fields
        String commaSepFieldList = evaluator.getConditionAdmissionList();
        if(commaSepFieldList == '') {
            return new List<String>();
        }
        System.debug(commaSepFieldList);

        // Query records with the fields received in the commSepFieldList String
        evaluator.getObjectRecords(commaSepFieldList);
        if(evaluator.recordsList.size() == 0 || evaluator.recordsList == null) {
            return new List<String>();
        }
        System.debug(evaluator.recordsList);

        // Query Tasks and form the mappingAndRecordTaskMap
        evaluator.createTasksMap();
        if(evaluator.mappingAndRecordTaskMap == null || evaluator.mappingAndRecordTaskMap.size() == 0) {
            return new List<String>();
        }

        // Evaluate Conditions Criteria
        System.debug('Criteria Evaluation Start');
        List<Task> taskUpdateList = evaluator.beginConditionCriteriaEval();
        If(taskUpdateList == null || taskUpdateList.size() == 0) {
            return new List<String>();
        }

        // Final Update of Tasks List
        update taskUpdateList;

        return new List<String>();
    }

    String getConditionAdmissionList() {

        // Initialize
        String commaSepFieldList = '';

        // Get Conditions Admission Mapping
        List<Conditions_Admission_Mapping__mdt> conditionAdmissionsMappingList = 
        [
            SELECT Id, MasterLabel, Boolean_Logic__c, Object_Api_Name__c, RLA_Relationship_Field_Api_Name__c, Field_To_Update_Api_Name__c, Field_Truthy_Update_Value__c, Field_Falsy_Update_Value__c
            FROM Conditions_Admission_Mapping__mdt
            WHERE Object_Api_Name__c = :this.objectApiName  WITH SECURITY_ENFORCED
        ];

        // Return if no Mapping exists for this object
        if(conditionAdmissionsMappingList.size() == 0) {
            return '';
        }

        // Create set of mappings
        Set<Id> setOfMappingIds = new Set<Id>();
        this.conditionsSubjectsSet = new Set<String>();
        this.relationshipFieldName = conditionAdmissionsMappingList[0].RLA_Relationship_Field_Api_Name__c;
        this.mappingMap = new Map<Id, Conditions_Admission_Mapping__mdt>();
        for(Conditions_Admission_Mapping__mdt cam:conditionAdmissionsMappingList) {
            setOfMappingIds.add(cam.Id);
            mappingMap.put(cam.Id, cam);
            this.conditionsSubjectsSet.add(cam.MasterLabel);
            if(!commaSepFieldList.contains(cam.RLA_Relationship_Field_Api_Name__c)) {
                commaSepFieldList = commaSepFieldList + cam.RLA_Relationship_Field_Api_Name__c+',';
            }
        }

        // Get Conditions Admission Criteria related to the mappings
        List<Conditions_Admission_Criterion__mdt> conditionAdmissionsCriteriaList = 
        [
            SELECT Id, MasterLabel, Conditions_Admission_Mapping__c, Field_Api_Name__c, Operator__c, Value__c
            FROM Conditions_Admission_Criterion__mdt
            WHERE Conditions_Admission_Mapping__c IN :setOfMappingIds  WITH SECURITY_ENFORCED
        ];

        // Return if no Criteria exists for this object
        if(conditionAdmissionsCriteriaList.size() == 0) {
            return '';
        }

        //Variables Initialization
        this.mappingToCriteriaMap = new Map<Id,List<Conditions_Admission_Criterion__mdt>>();
        

        // Initialization of mappingToCriteriaMap
        for(Conditions_Admission_Criterion__mdt cac:conditionAdmissionsCriteriaList) {
            if(!commaSepFieldList.contains(cac.Field_Api_Name__c)) {
                commaSepFieldList = commaSepFieldList + cac.Field_Api_Name__c + ',';
            }

            if(!this.mappingToCriteriaMap.containsKey(cac.Conditions_Admission_Mapping__c)) {
                this.mappingToCriteriaMap.put(cac.Conditions_Admission_Mapping__c, new List<Conditions_Admission_Criterion__mdt>());
            }
            this.mappingToCriteriaMap.get(cac.Conditions_Admission_Mapping__c).add(cac);

        }
        System.debug(commaSepFieldList);
        commaSepFieldList = commaSepFieldList.removeEnd(',');
        return commaSepFieldList;
        
    }

    void getObjectRecords(String commaSepFieldList) {
        System.debug(listOfIds);
        
        // Query Object 
        String query = 
        'SELECT ' + String.escapeSingleQuotes(commaSepFieldList) 
            + ' FROM ' +  String.escapeSingleQuotes(this.objectApiName) 
            + ' WHERE Id IN :listOfIds';
        System.debug(query);
        try {
        	this.recordsList = Database.query(query);
        } catch(Exception e) {
            throw new CustomMalformedQueryException('ConditionAdmissionEvaluator.invokeConditionAdmissionEvaluator Error: Condition Admissions Mapping/Criteria Custom Metadata Types for object ' 
                                                    + this.objectApiName + 
                                                    ' have incorrect values for RLA Relationship Field Api Name or Field Api Names.');
        }
        if(this.objectApiName != 'ResidentialLoanApplication') {
            listOfRlaIds = new List<Id>();
            for(SObject rec: this.recordsList) {
                listOfRlaIds.add(String.valueOf(rec.get(relationshipFieldName)));
            }
        }
    }

    void createTasksMap() {
        List<Id> taskWhatIdList;
        if(this.objectApiName != 'ResidentialLoanApplication') {
        	taskWhatIdList = listOfRlaIds;
        } else {
            taskWhatIdList = listOfIds;
        }
        
        
        
        String query = 
            'SELECT Id, Subject, WhatId FROM Task WHERE WhatId IN :taskWhatIdList AND Subject IN :conditionsSubjectsSet';
        System.debug(query);
        List<Task> taskList;
        try{
        	taskList = Database.query(query);
        } catch(Exception e) {
            throw new CustomMalformedQueryException('ConditionAdmissionEvaluator.invokeConditionAdmissionEvaluator Error: Unexpected error when querying tasks for '+ this.objectApiName+'. Details: '+e.getMessage());
        }
        System.debug(taskList);
        if(taskList.size() == 0) {
            return;
        }
        
        this.mappingAndRecordTaskMap = new Map<String, Task>();
        for(Task t:taskList) {
            this.mappingAndRecordTaskMap.put(t.WhatId + t.Subject, t);
        }
        System.debug(this.mappingAndRecordTaskMap);

    }

    List<Task> beginConditionCriteriaEval() {
        // TODO
        // For Each Condition Mappings
        //   For Each Record
        //     For Each Condition Criteria
        //       Evaluate Each Condition Criteria
        //       // TODO
        //       // Map Value to Correct Type based on Type of Field Api Name
        //       // Map Operator Correctly
        //       // Handle NULL correctly in Value
        //     Add Task List Entry
        // return Task List

        List<Task> tasksToUpdate = new List<Task>();
        for(Id mappingId:mappingMap.keyset()) {
            String boolOperator = mappingMap.get(mappingId).Boolean_Logic__c;
            for(sObject objectRecord: this.recordsList) {
                Boolean value;
                for(Conditions_Admission_Criterion__mdt criterion: mappingToCriteriaMap.get(mappingId)) {
                    if(value == null) {
                        value = this.evaluate(objectRecord.get(criterion.Field_Api_Name__c), getFieldType(criterion.Field_Api_Name__c), criterion.Operator__c, criterion.Value__c);
                    } else if(boolOperator == 'AND') {
                        value = value && this.evaluate(objectRecord.get(criterion.Field_Api_Name__c), getFieldType(criterion.Field_Api_Name__c), criterion.Operator__c, criterion.Value__c);
                    } else if(boolOperator == 'OR') {
                        value = value || this.evaluate(objectRecord.get(criterion.Field_Api_Name__c), getFieldType(criterion.Field_Api_Name__c), criterion.Operator__c, criterion.Value__c);
                    }
                    System.debug('field api name:'+getFieldType(criterion.Field_Api_Name__c));

                    System.debug('Value:'+value);
               }
                String valueToBeSet;
                if(value == true) {
					valueToBeSet = mappingMap.get(mappingId).Field_Truthy_Update_Value__c;                    
                } else {
                    valueToBeSet = mappingMap.get(mappingId).Field_Falsy_Update_Value__c;
                }
                
                Task t = new Task();
                t.put('Id',mappingAndRecordTaskMap.get(objectRecord.get(relationshipFieldName) +  mappingMap.get(mappingId).MasterLabel).Id);
                t.put(mappingMap.get(mappingId).Field_To_Update_Api_Name__c, valueToBeSet);
                tasksToUpdate.add(t);
                
            }
        }
        return tasksToUpdate;
    }

    Boolean evaluate(Object operator, String operatorType, String operation, String operand) {
        operatorType = operatorType.toUpperCase();
        
        System.debug('##Operator:'+operator+'##type:'+operatorType+'##operation:'+operation+'##operand'+operand);
        
        if(operatorType == 'STRING' || operatorType == 'PHONE' || operatorType == 'EMAIL' 
            || operatorType == 'PICKLIST' || operatorType == 'ENCRYPTEDSTRING' || operatorType == 'REFERENCE'
            || operatorType == 'TEXTAREA' || operatorType == 'URL' || operatorType == 'COMBOBOX'
            || operatorType == 'ID'
            ) {
                String castedOperator;
                String castedOperand;
                if(operator == null) {
                	castedOperator = '';
                } else {
                    castedOperator = String.valueOf(operator);
                }
                
                if(operand == null) {
                	castedOperand  ='';
                } else {
                    castedOperand = String.valueOf(operand);
                }
                
                switch on operation {
                    when 'Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Equal To' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than' {
                        return castedOperator.compareTo(castedOperand) > 0;
                    }
                    when 'Greater Than Equal To' {
                        return castedOperator.compareTo(castedOperand) >= 0;
                    }
                    when 'Lesser Than' {
                        return castedOperator.compareTo(castedOperand) < 0;
                    }
                    when 'Lesser Than Equal To' {
                        return castedOperator.compareTo(castedOperand) <= 0;
                    }
                    when 'Contains' {
                        return castedOperator.contains(castedOperand);
                    }
                    when 'Not Contains' {
                        return !castedOperator.contains(castedOperand);
                    }
                    when 'In' {
                        return castedOperand.contains(castedOperator);
                    }
                    when 'Not In' {
                        return !castedOperand.contains(castedOperator);
                    }
                    when else {
                        return null;
                    }
                }
            } else if(operatorType == 'BOOLEAN') {
                Boolean castedOperator = Boolean.valueOf(operator);
                Boolean castedOperand = Boolean.valueOf(operand.deleteWhitespace().toLowerCase());

                switch on operation {
                    when 'Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Equal To' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Lesser Than' {
                        return castedOperator != castedOperand;
                    }
                    when 'Lesser Than Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Contains' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Contains' {
                        return castedOperator != castedOperand;
                    }
                    when 'In' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not In' {
                        return castedOperator != castedOperand;
                    }
                    when else {
                        return null;
                    }
                }
            }else if(operatorType == 'DOUBLE' || operatorType == 'CURRENCY' || operatorType == 'PERCENT') {
                if(operator == null || operand == null) return false;
                
                Double castedOperator = Double.valueOf(String.valueOf(operator).deleteWhitespace());
                Double castedOperand = Double.valueOf(operand.deleteWhitespace());

                switch on operation {
                    when 'Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Equal To' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than' {
                        return castedOperator > castedOperand;
                    }
                    when 'Greater Than Equal To' {
                        return castedOperator >= castedOperand;
                    }
                    when 'Lesser Than' {
                        return castedOperator < castedOperand;
                    }
                    when 'Lesser Than Equal To' {
                        return castedOperator <= castedOperand;
                    }
                    when 'Contains' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Contains' {
                        return castedOperator != castedOperand;
                    }
                    when 'In' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not In' {
                        return castedOperator != castedOperand;
                    }
                    when else {
                        return null;
                    }
                }
                } else if(operatorType == 'INTEGER' || operatorType == 'LONG') {
                
                if(operator == null || operand == null) return false;

                Long castedOperator = Long.valueOf(String.valueOf(operator).deleteWhitespace());
                Long castedOperand = Long.valueOf(operand.deleteWhitespace());

                switch on operation {
                    when 'Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Equal To' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than' {
                        return castedOperator > castedOperand;
                    }
                    when 'Greater Than Equal To' {
                        return castedOperator >= castedOperand;
                    }
                    when 'Lesser Than' {
                        return castedOperator < castedOperand;
                    }
                    when 'Lesser Than Equal To' {
                        return castedOperator <= castedOperand;
                    }
                    when 'Contains' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Contains' {
                        return castedOperator != castedOperand;
                    }
                    when 'In' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not In' {
                        return castedOperator != castedOperand;
                    }
                    when else {
                        return null;
                    }
                }

            } else if(operatorType == 'DATE' || operatorType == 'DATETIME') {
                if(operator == null || operand == null) return false;

                DateTime castedOperator;
                DateTime castedOperand;
                if(operatorType == 'DATE') {
                    castedOperator = DateTime.parse(String.valueOf(operator).deleteWhitespace().toLowerCase()+'00:00:00.000Z');
                	castedOperand = DateTime.parse(String.valueOf(operand).deleteWhitespace().toLowerCase()+'00:00:00.000Z');
                } else {
                	
                    castedOperator = DateTime.parse(String.valueOf(operator).deleteWhitespace().toLowerCase());
                	castedOperand = DateTime.parse(String.valueOf(operand).deleteWhitespace().toLowerCase());
                }

                switch on operation {
                    when 'Equal To' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Equal To' {
                        return castedOperator != castedOperand;
                    }
                    when 'Greater Than' {
                        return castedOperator > castedOperand;
                    }
                    when 'Greater Than Equal To' {
                        return castedOperator >= castedOperand;
                    }
                    when 'Lesser Than' {
                        return castedOperator < castedOperand;
                    }
                    when 'Lesser Than Equal To' {
                        return castedOperator <= castedOperand;
                    }
                    when 'Contains' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not Contains' {
                        return castedOperator != castedOperand;
                    }
                    when 'In' {
                        return castedOperator == castedOperand;
                    }
                    when 'Not In' {
                        return castedOperator != castedOperand;
                    }
                    when else {
                        return null;
                    }
                }
            }
            return false;
        }

    String getFieldType(String fieldName) {
        SObjectType r = ((SObject)(Type.forName('Schema.'+objectApiName).newInstance())).getSObjectType();
        DescribeSObjectResult d = r.getDescribe();
        return String.valueOf(d.fields.getMap().get(fieldName).getDescribe().getType());
    }
}