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

        // Get Records
        evaluator.getObjectRecords(commaSepFieldList);
        if(evaluator.recordsList.size() == 0 || evaluator.recordsList == null) {
            return new List<String>();
        }

        // Get Tasks
        evaluator.createTasksMap();
        if(evaluator.mappingAndRecordTaskMap == null || evaluator.mappingAndRecordTaskMap.size() == 0) {
            return new List<String>();
        }

        // Evaluate Conditions Criteria
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
            + ' WHERE ' +  String.escapeSingleQuotes(this.relationshipFieldName)
            + ' IN :listOfIds';
        System.debug(query);
        try {
        	this.recordsList = Database.query(query);
        } catch(Exception e) {
            throw new CustomMalformedQueryException('ConditionAdmissionEvaluator.invokeConditionAdmissionEvaluator Error: Condition Admissions Mapping/Criteria Custom Metadata Types for object ' 
                                                    + this.objectApiName + 
                                                    ' have incorrect values for RLA Relationship Field Api Name or Field Api Names.');
        }
    }

    void createTasksMap() {
        
        String query = 
            'SELECT Id, Subject, WhatId FROM Task WHERE WhatId IN :listOfIds AND Subject IN :conditionsSubjectsSet';
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
        return new List<Task>();
    }
}