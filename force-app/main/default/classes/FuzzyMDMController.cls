public with sharing class FuzzyMDMController {
  @AuraEnabled(cacheable=true)
  public static List<String> getObjects() {
    List<String> objects = new List<String>();
    for (Schema.SObjectType sObjectType : Schema.getGlobalDescribe().values()) {
      Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
      if (describe.isAccessible() && describe.isQueryable() && !describe.isCustomSetting()) {
        objects.add(describe.getName());
      }
    }
    objects.sort();
    return objects;
  }

  @AuraEnabled(cacheable=true)
  public static List<String> getFields(String objectName) {
    List<String> fields = new List<String>();
    if (String.isBlank(objectName)) {
      return fields;
    }

    Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
    if (sObjectType == null) {
      return fields;
    }

    for (Schema.SObjectField field : sObjectType.getDescribe().fields.getMap().values()) {
      Schema.DescribeFieldResult describe = field.getDescribe();
      if (describe.isAccessible() && describe.getType() == Schema.DisplayType.STRING) {
        fields.add(describe.getName());
      }
    }
    fields.sort();
    return fields;
  }

  @AuraEnabled(cacheable=true)
  public static Boolean hasDependentObjects(String objectName) {
    if (String.isBlank(objectName)) {
      return false;
    }

    Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
    if (sObjectType == null) {
      return false;
    }

    for (Schema.ChildRelationship rel : sObjectType.getDescribe().getChildRelationships()) {
      if (rel.getRelationshipName() != null && rel.getChildSObject().getDescribe().isUpdateable()) {
        return true;
      }
    }

    for (Schema.SObjectType relatedType : Schema.getGlobalDescribe().values()) {
      for (Schema.SObjectField field : relatedType.getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && fieldDescribe.isUpdateable()) {
          List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
          if (referenceTo != null && !referenceTo.isEmpty() && referenceTo[0].getDescribe().getName() == objectName) {
            return true;
          }
        }
      }
    }
    return false;
  }

  @AuraEnabled
  public static void startMDMProcess(String objectName, List<String> fields, Map<String, Integer> fieldThresholds, Boolean includeDependents, Boolean runNow, String errorEmails) {
    try {
      if (String.isBlank(objectName) || fields == null || fields.isEmpty() || fieldThresholds == null) {
        throw new AuraHandledException('Invalid input parameters.');
      }

      for (String field : fields) {
        if (!fieldThresholds.containsKey(field) || fieldThresholds.get(field) < 0 || fieldThresholds.get(field) > 100) {
          throw new AuraHandledException('Invalid threshold for field: ' + field);
        }
      }

      Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
      if (sObjectType == null) {
        throw new AuraHandledException('Invalid object name.');
      }

      Integer batchJobsLimit = 5;
      Integer currentBatchJobs = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND (Status = 'Processing' OR Status = 'Holding' OR Status = 'Queued')];
      if (currentBatchJobs >= batchJobsLimit) {
        throw new AuraHandledException('Cannot start MDM process: Maximum number of batch jobs (' + batchJobsLimit + ') are already running.');
      }

      if (runNow) {
        FuzzyMDMBatch batch = new FuzzyMDMBatch(objectName, fields, fieldThresholds, includeDependents, errorEmails);
        Id batchJobId = Database.executeBatch(batch, 50);
        System.debug('Batch job started with ID: ' + batchJobId);
      }
    } catch (Exception e) {
      throw new AuraHandledException('Error starting MDM process: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static void scheduleMDMProcess(String objectName, List<String> fields, Map<String, Integer> fieldThresholds, Boolean includeDependents, String scheduleTime, Boolean isScheduled, String errorEmails) {
    try {
      if (String.isBlank(objectName) || fields == null || fields.isEmpty() || fieldThresholds == null) {
        throw new AuraHandledException('Invalid input parameters.');
      }

      for (String field : fields) {
        if (!fieldThresholds.containsKey(field) || fieldThresholds.get(field) < 0 || fieldThresholds.get(field) > 100) {
          throw new AuraHandledException('Invalid threshold for field: ' + field);
        }
      }

      if (isScheduled && String.isBlank(scheduleTime)) {
        throw new AuraHandledException('Schedule time is required when scheduling is enabled.');
      }

      MDM_Schedule_Setting__c existingSetting = getScheduleSetting();
      if (existingSetting != null && existingSetting.Object_Name__c == objectName && existingSetting.Is_Scheduled__c && isScheduled) {
        if (existingSetting.Fields__c == JSON.serialize(fields) &&
            existingSetting.Field_Thresholds__c == JSON.serialize(fieldThresholds) &&
            existingSetting.Include_Dependents__c == includeDependents &&
            existingSetting.Error_Notification_Emails__c == errorEmails &&
            existingSetting.Schedule_Time__c != scheduleTime) {
          if (existingSetting.Schedule_Job_Id__c != null) {
            System.abortJob(existingSetting.Schedule_Job_Id__c);
          }
          List<String> timeParts = scheduleTime.split(':');
          Integer hour = Integer.valueOf(timeParts[0]);
          Integer minute = Integer.valueOf(timeParts[1]);
          String cronExpression = '0 ' + minute + ' ' + hour + ' * * ?';
          FuzzyMDMScheduler scheduler = new FuzzyMDMScheduler(objectName, fields, fieldThresholds, includeDependents, errorEmails);
          String jobId = System.schedule('Fuzzy MDM Daily Job - ' + objectName, cronExpression, scheduler);
          saveScheduleSettings(objectName, fields, fieldThresholds, includeDependents, scheduleTime, true, jobId, errorEmails);
          return;
        } else {
          throw new AuraHandledException('A scheduled job already exists for this object. Please remove the existing schedule first.');
        }
      }

      if (existingSetting != null && existingSetting.Schedule_Job_Id__c != null) {
        try {
          System.abortJob(existingSetting.Schedule_Job_Id__c);
        } catch (Exception e) {
          System.debug('Error aborting existing job: ' + e.getMessage());
        }
      }

      String jobId = null;
      if (isScheduled) {
        List<String> timeParts = scheduleTime.split(':');
        Integer hour = Integer.valueOf(timeParts[0]);
        Integer minute = Integer.valueOf(timeParts[1]);
        String cronExpression = '0 ' + minute + ' ' + hour + ' * * ?';
        FuzzyMDMScheduler scheduler = new FuzzyMDMScheduler(objectName, fields, fieldThresholds, includeDependents, errorEmails);
        jobId = System.schedule('Fuzzy MDM Daily Job - ' + objectName, cronExpression, scheduler);
      }

      saveScheduleSettings(objectName, fields, fieldThresholds, includeDependents, scheduleTime, isScheduled, jobId, errorEmails);
    } catch (Exception e) {
      throw new AuraHandledException('Error scheduling MDM process: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static Map<String, Object> getScheduleSettings() {
    MDM_Schedule_Setting__c setting = getScheduleSetting();
    if (setting == null) {
      return null;
    }

    Map<String, Object> settings = new Map<String, Object>();
    settings.put('objectName', setting.Object_Name__c);
    settings.put('fields', (List<String>)JSON.deserialize(setting.Fields__c, List<String>.class));
    settings.put('fieldThresholds', (Map<String, Integer>)JSON.deserialize(setting.Field_Thresholds__c, Map<String, Integer>.class));
    settings.put('includeDependents', setting.Include_Dependents__c);
    settings.put('scheduleTime', setting.Schedule_Time__c);
    settings.put('isScheduled', setting.Is_Scheduled__c);
    settings.put('errorEmails', setting.Error_Notification_Emails__c);
    return settings;
  }

  @AuraEnabled
  public static void removeScheduledJob() {
    MDM_Schedule_Setting__c setting = getScheduleSetting();
    if (setting != null && setting.Schedule_Job_Id__c != null) {
      try {
        System.abortJob(setting.Schedule_Job_Id__c);
        saveScheduleSettings(
          setting.Object_Name__c,
          (List<String>)JSON.deserialize(setting.Fields__c, List<String>.class),
          (Map<String, Integer>)JSON.deserialize(setting.Field_Thresholds__c, Map<String, Integer>.class),
          setting.Include_Dependents__c,
          setting.Schedule_Time__c,
          false,
          null,
          setting.Error_Notification_Emails__c
        );
      } catch (Exception e) {
        throw new AuraHandledException('Error removing scheduled job: ' + e.getMessage());
      }
    }
  }

  private static MDM_Schedule_Setting__c getScheduleSetting() {
    List<MDM_Schedule_Setting__c> settings = [
      SELECT Object_Name__c, Fields__c, Field_Thresholds__c, Include_Dependents__c, Schedule_Time__c, Is_Scheduled__c, Schedule_Job_Id__c, Error_Notification_Emails__c
      FROM MDM_Schedule_Setting__c
      WHERE DeveloperName__c = 'Default_Setting'
      LIMIT 1
    ];
    return settings.isEmpty() ? null : settings[0];
  }

  private static void saveScheduleSettings(String objectName, List<String> fields, Map<String, Integer> fieldThresholds, Boolean includeDependents, String scheduleTime, Boolean isScheduled, String jobId, String errorEmails) {
    MDM_Schedule_Setting__c setting = getScheduleSetting();
    if (setting == null) {
      setting = new MDM_Schedule_Setting__c(
        DeveloperName__c = 'Default_Setting'
      );
    }

    setting.Object_Name__c = objectName;
    setting.Fields__c = JSON.serialize(fields);
    setting.Field_Thresholds__c = JSON.serialize(fieldThresholds);
    setting.Include_Dependents__c = includeDependents;
    setting.Schedule_Time__c = scheduleTime;
    setting.Is_Scheduled__c = isScheduled;
    setting.Schedule_Job_Id__c = jobId;
    setting.Error_Notification_Emails__c = errorEmails;

    upsert setting;
  }
}