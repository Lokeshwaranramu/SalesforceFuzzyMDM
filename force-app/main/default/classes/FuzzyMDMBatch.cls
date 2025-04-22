/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-22-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class FuzzyMDMBatch implements Database.Batchable<sObject>, Database.Stateful {
  private String objectName;
  private List<String> fields;
  private Map<String, Integer> fieldThresholds;
  private Boolean includeDependents;
  private String errorEmails;
  private Map<String, List<Map<String, String>>> lookupRelationships;
  private Map<String, List<String>> childRelationships;
  private List<String> mergeErrors;

  public FuzzyMDMBatch(String objectName, List<String> fields, Map<String, Integer> fieldThresholds, Boolean includeDependents, String errorEmails) {
    this.objectName = objectName;
    this.fields = fields;
    this.fieldThresholds = fieldThresholds;
    this.includeDependents = includeDependents;
    this.errorEmails = errorEmails;
    this.lookupRelationships = new Map<String, List<Map<String, String>>>();
    this.childRelationships = new Map<String, List<String>>();
    this.mergeErrors = new List<String>();
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    String query = 'SELECT Id, LastModifiedDate, ' + String.join(fields, ', ') +
                   ' FROM ' + objectName +
                   ' WHERE ' + fields[0] + ' != NULL' +
                   ' WITH SECURITY_ENFORCED';
    return Database.getQueryLocator(query);
  }

  public void execute(Database.BatchableContext bc, List<sObject> scope) {
    Map<String, List<sObject>> groupedRecords = new Map<String, List<sObject>>();
    for (sObject record : scope) {
      String compositeKey = generateCompositeKey(record);
      if (!groupedRecords.containsKey(compositeKey)) {
        groupedRecords.put(compositeKey, new List<sObject>());
      }
      groupedRecords.get(compositeKey).add(record);
    }

    for (String key : groupedRecords.keySet()) {
      List<sObject> records = groupedRecords.get(key);
      if (records.size() <= 1) continue;

      records = sortByLastModified(records);
      sObject masterRecord = records[0];
      List<Id> duplicateIds = new List<Id>();
      for (Integer i = 1; i < records.size(); i++) {
        sObject duplicate = records[i];
        if (isDuplicate(masterRecord, duplicate)) {
          duplicateIds.add(duplicate.Id);
        }
      }

      if (!duplicateIds.isEmpty()) {
        try {
          mergeRecords(masterRecord, duplicateIds);
        } catch (Exception e) {
          mergeErrors.add('Failed to merge records for master ID ' + masterRecord.Id + ': ' + e.getMessage());
        }
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('Fuzzy MDM Batch completed for object: ' + objectName);
    if (!mergeErrors.isEmpty() && String.isNotBlank(errorEmails)) {
      sendErrorEmail();
    }
  }

  private String generateCompositeKey(sObject record) {
    String key = '';
    for (String field : fields) {
      String value = (String)record.get(field);
      if (String.isNotBlank(value)) {
        Integer charLimit = Math.min(value.length(), 5);
        key += value.substring(0, charLimit).toLowerCase() + '|';
      } else {
        key += '|';
      }
    }
    return key;
  }

  private Boolean isDuplicate(sObject master, sObject duplicate) {
    for (String field : fields) {
      String masterValue = (String)master.get(field);
      String duplicateValue = (String)duplicate.get(field);
      if (String.isBlank(masterValue) || String.isBlank(duplicateValue)) continue;

      Integer threshold = fieldThresholds.get(field);
      Integer similarity = calculateSimilarity(masterValue, duplicateValue);
      if (similarity < threshold) {
        return false;
      }
    }
    return true;
  }

  private Integer calculateSimilarity(String str1, String str2) {
    Integer charLimit = Math.min(Math.min(str1.length(), str2.length()), 5);
    str1 = str1.substring(0, charLimit).toLowerCase();
    str2 = str2.substring(0, charLimit).toLowerCase();

    Integer len1 = str1.length();
    Integer len2 = str2.length();
    if (len1 == 0) return len2 == 0 ? 100 : 0;
    if (len2 == 0) return 0;

    List<List<Integer>> dp = new List<List<Integer>>();
    for (Integer i = 0; i <= len1; i++) {
      List<Integer> row = new List<Integer>();
      for (Integer j = 0; j <= len2; j++) {
        row.add(0);
      }
      dp.add(row);
    }

    for (Integer i = 0; i <= len1; i++) dp[i][0] = i;
    for (Integer j = 0; j <= len2; j++) dp[0][j] = j;

    for (Integer i = 1; i <= len1; i++) {
      for (Integer j = 1; j <= len2; j++) {
        Integer cost = (str1.charAt(i - 1) == str2.charAt(j - 1)) ? 0 : 1;
        dp[i][j] = Math.min(
          Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost
        );
      }
    }

    Integer distance = dp[len1][len2];
    Integer maxLen = Math.max(len1, len2);
    return (Integer)((1.0 - (Double)distance / maxLen) * 100);
  }

  private void mergeRecords(sObject masterRecord, List<Id> duplicateIds) {
    if (includeDependents) {
      reparentDependentRecords(masterRecord.Id, duplicateIds);
      updateLookupRelationships(masterRecord.Id, duplicateIds);
    }

    // Query duplicate records to get all fields
    String query = 'SELECT Id, ' + String.join(fields, ', ') + ' FROM ' + objectName + 
                   ' WHERE Id IN :duplicateIds WITH SECURITY_ENFORCED';
    List<sObject> duplicates = Database.query(query);

    // Copy non-empty field values from duplicates to master
    copyNonEmptyFields(masterRecord, duplicates);

    // Update the master record with copied values
    Database.SaveResult updateResult = Database.update(masterRecord, false);
    if (!updateResult.isSuccess()) {
      throw new AuraHandledException('Failed to update master record: ' + updateResult.getErrors()[0].getMessage());
    }

    // Delete duplicate records
    String deleteQuery = 'SELECT Id FROM ' + objectName + ' WHERE Id IN :duplicateIds WITH SECURITY_ENFORCED';
    List<sObject> recordsToDelete = Database.query(deleteQuery);
    if (!recordsToDelete.isEmpty()) {
      Database.DeleteResult[] results = Database.delete(recordsToDelete, false);
      for (Database.DeleteResult result : results) {
        if (!result.isSuccess()) {
          throw new AuraHandledException('Failed to delete duplicate records: ' + result.getErrors()[0].getMessage());
        }
      }
    }
    System.debug('Merged ' + duplicateIds.size() + ' duplicates into master record: ' + masterRecord.Id);
  }

  private void copyNonEmptyFields(sObject masterRecord, List<sObject> duplicates) {
    // Get the describe result for the object to check field writability
    Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
    Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
    
    // Cache the writability of each field
    Map<String, Boolean> fieldWritability = new Map<String, Boolean>();
    for (String field : fields) {
      Schema.SObjectField sField = fieldMap.get(field);
      if (sField != null) {
        Schema.DescribeFieldResult fieldDescribe = sField.getDescribe();
        fieldWritability.put(field, fieldDescribe.isUpdateable() && fieldDescribe.isAccessible());
      } else {
        fieldWritability.put(field, false); // Field doesn't exist, mark as not writable
      }
    }

    // Copy fields only if they are writable
    for (sObject duplicate : duplicates) {
      for (String field : fields) {
        // Skip if the field is not writable
        if (!fieldWritability.get(field)) {
          continue;
        }

        Object masterValue = masterRecord.get(field);
        Object duplicateValue = duplicate.get(field);

        // Copy the duplicate value to master if master is null/empty and duplicate is not
        if ((masterValue == null || String.isBlank(String.valueOf(masterValue))) && 
            duplicateValue != null && String.isNotBlank(String.valueOf(duplicateValue))) {
          masterRecord.put(field, duplicateValue);
        }
      }
    }
  }

  private void reparentDependentRecords(Id masterId, List<Id> duplicateIds) {
    if (childRelationships.isEmpty()) {
      Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
      for (Schema.ChildRelationship rel : sObjectType.getDescribe().getChildRelationships()) {
        if (rel.getRelationshipName() != null && rel.getChildSObject().getDescribe().isUpdateable()) {
          String childObject = rel.getChildSObject().getDescribe().getName();
          String fieldName = rel.getField().getDescribe().getName();
          if (!childRelationships.containsKey(childObject)) {
            childRelationships.put(childObject, new List<String>());
          }
          childRelationships.get(childObject).add(fieldName);
        }
      }
    }

    for (String childObject : childRelationships.keySet()) {
      for (String fieldName : childRelationships.get(childObject)) {
        String query = 'SELECT Id, ' + fieldName + ' FROM ' + childObject +
                       ' WHERE ' + fieldName + ' IN :duplicateIds WITH SECURITY_ENFORCED';
        List<sObject> childRecords = Database.query(query);
        for (sObject child : childRecords) {
          child.put(fieldName, masterId);
        }
        if (!childRecords.isEmpty()) {
          Database.SaveResult[] results = Database.update(childRecords, false);
          for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
              throw new AuraHandledException('Failed to reparent child records: ' + result.getErrors()[0].getMessage());
            }
          }
        }
      }
    }
  }

  private void updateLookupRelationships(Id masterId, List<Id> duplicateIds) {
    if (lookupRelationships.isEmpty()) {
      Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectName);
      for (Schema.SObjectType relatedType : Schema.getGlobalDescribe().values()) {
        String relatedObjectName = relatedType.getDescribe().getName();
        for (Schema.SObjectField field : relatedType.getDescribe().fields.getMap().values()) {
          Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
          if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && fieldDescribe.isUpdateable()) {
            List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
            if (referenceTo != null && !referenceTo.isEmpty() && referenceTo[0].getDescribe().getName() == objectName) {
              if (!lookupRelationships.containsKey(relatedObjectName)) {
                lookupRelationships.put(relatedObjectName, new List<Map<String, String>>());
              }
              lookupRelationships.get(relatedObjectName).add(new Map<String, String>{
                'fieldName' => fieldDescribe.getName(),
                'relationshipName' => fieldDescribe.getRelationshipName()
              });
            }
          }
        }
      }
    }

    for (String relatedObject : lookupRelationships.keySet()) {
      for (Map<String, String> fieldInfo : lookupRelationships.get(relatedObject)) {
        String fieldName = fieldInfo.get('fieldName');
        String query = 'SELECT Id, ' + fieldName + ' FROM ' + relatedObject +
                       ' WHERE ' + fieldName + ' IN :duplicateIds WITH SECURITY_ENFORCED';
        List<sObject> relatedRecords = Database.query(query);
        for (sObject related : relatedRecords) {
          related.put(fieldName, masterId);
        }
        if (!relatedRecords.isEmpty()) {
          Database.SaveResult[] results = Database.update(relatedRecords, false);
          for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
              throw new AuraHandledException('Failed to update lookup field ' + fieldName + ' on ' + relatedObject + ': ' + result.getErrors()[0].getMessage());
            }
          }
        }
      }
    }
  }

  private List<sObject> sortByLastModified(List<sObject> records) {
    List<SortWrapper> wrappers = new List<SortWrapper>();
    for (sObject record : records) {
      wrappers.add(new SortWrapper(record));
    }
    wrappers.sort();
    List<sObject> sortedRecords = new List<sObject>();
    for (SortWrapper wrapper : wrappers) {
      sortedRecords.add(wrapper.record);
    }
    return sortedRecords;
  }

  private void sendErrorEmail() {
    if (String.isBlank(errorEmails)) return;

    List<String> emailList = errorEmails.split(',');
    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setToAddresses(emailList);
    email.setSubject('Fuzzy MDM Batch Errors for ' + objectName);
    email.setPlainTextBody('The following errors occurred during the MDM process:\n\n' + String.join(mergeErrors, '\n'));
    Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
  }

  private class SortWrapper implements Comparable {
    public sObject record;

    public SortWrapper(sObject record) {
      this.record = record;
    }

    public Integer compareTo(Object compareTo) {
      SortWrapper other = (SortWrapper)compareTo;
      DateTime d1 = (DateTime)record.get('LastModifiedDate');
      DateTime d2 = (DateTime)other.record.get('LastModifiedDate');
      if (d1 > d2) return -1;
      if (d1 < d2) return 1;
      return 0;
    }
  }
}