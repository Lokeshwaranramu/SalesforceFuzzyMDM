({
  getObjects: function(component) {
    const action = component.get("c.getObjects");
    action.setCallback(this, function(response) {
      const state = response.getState();
      if (state === "SUCCESS") {
        component.set("v.objects", response.getReturnValue());
      } else {
        this.showToast(component, "Error", "Failed to fetch objects: " + response.getError()[0].message, "error");
      }
    });
    $A.enqueueAction(action);
  },

  getFields: function(component) {
    const action = component.get("c.getFields");
    action.setParams({ objectName: component.get("v.selectedObject") });
    action.setCallback(this, function(response) {
      const state = response.getState();
      if (state === "SUCCESS") {
        const fields = response.getReturnValue().map(field => ({
          label: field,
          value: field
        }));
        component.set("v.fields", fields);
      } else {
        this.showToast(component, "Error", "Failed to fetch fields: " + response.getError()[0].message, "error");
      }
    });
    $A.enqueueAction(action);
  },

  loadScheduleSettings: function(component) {
    const action = component.get("c.getScheduleSettings");
    action.setCallback(this, function(response) {
      const state = response.getState();
      if (state === "SUCCESS") {
        const settings = response.getReturnValue();
        if (settings) {
          component.set("v.selectedObject", settings.objectName);
          component.set("v.selectedFields", settings.fields);
          const fieldThresholdList = [];
          for (let field of settings.fields) {
            fieldThresholdList.push({
              field: field,
              threshold: settings.fieldThresholds[field] || 80
            });
          }
          component.set("v.fieldThresholdList", fieldThresholdList);
          component.set("v.includeDependents", settings.includeDependents);
          component.set("v.scheduleTime", settings.scheduleTime);
          component.set("v.isScheduled", settings.isScheduled);
          component.set("v.errorEmails", settings.errorEmails);
          component.set("v.isJobScheduledForObject", settings.isScheduled);
          if (settings.isScheduled) {
            component.set("v.startButtonLabel", "Terminate MDM Process");
          }

          if (settings.objectName) {
            this.getFields(component);
            const dependentAction = component.get("c.hasDependentObjects");
            dependentAction.setParams({ objectName: settings.objectName });
            dependentAction.setCallback(this, function(depResponse) {
              const depState = depResponse.getState();
              if (depState === "SUCCESS") {
                const hasDependents = depResponse.getReturnValue();
                component.set("v.hasDependents", hasDependents);
                if (!hasDependents) {
                  component.set("v.includeDependents", false);
                }
              } else {
                this.showToast(component, "Error", "Failed to check dependent objects: " + depResponse.getError()[0].message, "error");
              }
            });
            $A.enqueueAction(dependentAction);
          }
        }
      } else {
        this.showToast(component, "Error", "Failed to load schedule settings: " + response.getError()[0].message, "error");
      }
    });
    $A.enqueueAction(action);
  },

  showToast: function(component, title, message, variant) {
    const toastEvent = $A.get("e.force:showToast");
    toastEvent.setParams({
      title: title,
      message: message,
      type: variant
    });
    toastEvent.fire();
  }
})