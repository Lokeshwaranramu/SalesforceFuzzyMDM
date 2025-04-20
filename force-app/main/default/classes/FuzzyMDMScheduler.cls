public with sharing class FuzzyMDMScheduler implements Schedulable {
  private String objectName;
  private List<String> fields;
  private Map<String, Integer> fieldThresholds;
  private Boolean includeDependents;
  private String errorEmails;

  public FuzzyMDMScheduler(String objectName, List<String> fields, Map<String, Integer> fieldThresholds, Boolean includeDependents, String errorEmails) {
    this.objectName = objectName;
    this.fields = fields;
    this.fieldThresholds = fieldThresholds;
    this.includeDependents = includeDependents;
    this.errorEmails = errorEmails;
  }

  public void execute(SchedulableContext sc) {
    FuzzyMDMBatch batch = new FuzzyMDMBatch(objectName, fields, fieldThresholds, includeDependents, errorEmails);
    Database.executeBatch(batch, 50);
  }
}