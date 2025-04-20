({
  doInit: function(component, event, helper) {
    helper.loadScheduleSettings(component);
    helper.getObjects(component);
  },

  handleObjectChange: function(component, event, helper) {
    const selectedObject = event.getSource().get("v.value");
    component.set("v.selectedObject", selectedObject);
    component.set("v.selectedFields", []);
    component.set("v.fieldThresholdList", []);
    component.set("v.includeDependents", false);
    component.set("v.hasDependents", false);
    component.set("v.isJobScheduledForObject", false);
    component.set("v.startButtonLabel", "Start MDM Process Now");

    if (selectedObject) {
      helper.getFields(component);
      const action = component.get("c.hasDependentObjects");
      action.setParams({ objectName: selectedObject });
      action.setCallback(this, function(response) {
        const state = response.getState();
        if (state === "SUCCESS") {
          const hasDependents = response.getReturnValue();
          component.set("v.hasDependents", hasDependents);
          if (!hasDependents) {
            component.set("v.includeDependents", false);
          }
        } else {
          helper.showToast(component, "Error", "Failed to check dependent objects: " + response.getError()[0].message, "error");
        }
      });
      $A.enqueueAction(action);

      const settingsAction = component.get("c.getScheduleSettings");
      settingsAction.setCallback(this, function(settingsResponse) {
        const settingsState = settingsResponse.getState();
        if (settingsState === "SUCCESS") {
          const settings = settingsResponse.getReturnValue();
          if (settings && settings.objectName === selectedObject && settings.isScheduled) {
            component.set("v.isJobScheduledForObject", true);
            component.set("v.startButtonLabel", "Terminate MDM Process");
          }
        }
      });
      $A.enqueueAction(settingsAction);
    } else {
      component.set("v.fields", []);
    }
  },

  handleFieldChange: function(component, event, helper) {
    const selectedFields = event.getSource().get("v.value");
    const currentThresholdList = component.get("v.fieldThresholdList");
    const currentThresholdMap = {};
    currentThresholdList.forEach(item => {
      currentThresholdMap[item.field] = item.threshold;
    });

    const newThresholdList = [];
    for (let field of selectedFields) {
      newThresholdList.push({
        field: field,
        threshold: currentThresholdMap[field] || 80
      });
    }
    component.set("v.selectedFields", selectedFields);
    component.set("v.fieldThresholdList", newThresholdList);
  },

  handleThresholdChange: function(component, event, helper) {
    const index = parseInt(event.getSource().get("v.name"));
    const value = parseInt(event.getSource().get("v.value"));
    const thresholdList = component.get("v.fieldThresholdList");
    thresholdList[index].threshold = value;
    component.set("v.fieldThresholdList", thresholdList);
  },

  handleDependentChange: function(component, event, helper) {
    const include = event.getSource().get("v.checked");
    component.set("v.includeDependents", include);
  },

  handleErrorEmailsChange: function(component, event, helper) {
    component.set("v.errorEmails", event.getSource().get("v.value"));
  },

  handleScheduleTimeChange: function(component, event, helper) {
    component.set("v.scheduleTime", event.getSource().get("v.value"));
  },

  handleScheduleChange: function(component, event, helper) {
    const isScheduled = event.getSource().get("v.checked");
    component.set("v.isScheduled", isScheduled);
  },

  handleStartButtonClick: function(component, event, helper) {
    if (component.get("v.isJobScheduledForObject")) {
      component.set("v.isProcessing", true);
      const action = component.get("c.removeScheduledJob");
      action.setCallback(this, function(response) {
        const state = response.getState();
        component.set("v.isProcessing", false);
        if (state === "SUCCESS") {
          component.set("v.isScheduled", false);
          component.set("v.isJobScheduledForObject", false);
          component.set("v.startButtonLabel", "Start MDM Process Now");
          helper.showToast(component, "Success", "Scheduled MDM process terminated.", "success");
        } else {
          helper.showToast(component, "Error", response.getError()[0].message, "error");
        }
      });
      $A.enqueueAction(action);
    } else {
      const selectedObject = component.get("v.selectedObject");
      const selectedFields = component.get("v.selectedFields");
      const fieldThresholdList = component.get("v.fieldThresholdList");
      const includeDependents = component.get("v.includeDependents");
      const errorEmails = component.get("v.errorEmails");

      if (!selectedObject || selectedFields.length === 0) {
        helper.showToast(component, "Error", "Please select an object and at least one field.", "error");
        return;
      }

      const fieldThresholds = {};
      for (let item of fieldThresholdList) {
        const threshold = item.threshold;
        if (threshold == null || threshold < 0 || threshold > 100) {
          helper.showToast(component, "Error", "Threshold for " + item.field + " must be between 0 and 100.", "error");
          return;
        }
        fieldThresholds[item.field] = threshold;
      }

      component.set("v.isProcessing", true);
      const action = component.get("c.startMDMProcess");
      action.setParams({
        objectName: selectedObject,
        fields: selectedFields,
        fieldThresholds: fieldThresholds,
        includeDependents: includeDependents,
        runNow: true,
        errorEmails: errorEmails
      });
      action.setCallback(this, function(response) {
        const state = response.getState();
        component.set("v.isProcessing", false);
        if (state === "SUCCESS") {
          helper.showToast(component, "Success", "MDM Process started! Check Debug Logs for progress.", "success");
        } else {
          helper.showToast(component, "Error", response.getError()[0].message, "error");
        }
      });
      $A.enqueueAction(action);
    }
  },

  saveSchedule: function(component, event, helper) {
    const selectedObject = component.get("v.selectedObject");
    const selectedFields = component.get("v.selectedFields");
    const fieldThresholdList = component.get("v.fieldThresholdList");
    const includeDependents = component.get("v.includeDependents");
    let scheduleTime = component.get("v.scheduleTime");
    const isScheduled = component.get("v.isScheduled");
    const errorEmails = component.get("v.errorEmails");

    if (!selectedObject || selectedFields.length === 0) {
      helper.showToast(component, "Error", "Please select an object and at least one field to schedule.", "error");
      return;
    }

    const fieldThresholds = {};
    for (let item of fieldThresholdList) {
      const threshold = item.threshold;
      if (threshold == null || threshold < 0 || threshold > 100) {
        helper.showToast(component, "Error", "Threshold for " + item.field + " must be between 0 and 100.", "error");
        return;
      }
      fieldThresholds[item.field] = threshold;
    }

    if (isScheduled) {
      if (!scheduleTime) {
        helper.showToast(component, "Error", "Please provide a valid time.", "error");
        return;
      }

      // Trim any extra whitespace
      scheduleTime = scheduleTime.trim();

      // Log the raw scheduleTime for debugging
      console.log('Raw scheduleTime:', scheduleTime);

      // Check for 12-hour format (e.g., "2:45 AM")
      const twelveHourParts = scheduleTime.match(/^(0?\d|1[0-2]):([0-5]\d)\s*(AM|PM)$/i);
      if (twelveHourParts) {
        let hours = parseInt(twelveHourParts[1], 10);
        const minutes = twelveHourParts[2];
        const period = twelveHourParts[3].toUpperCase();

        // Convert 12-hour to 24-hour format
        if (period === "AM" && hours === 12) {
          hours = 0;
        } else if (period === "PM" && hours !== 12) {
          hours += 12;
        }

        // Format as HH:mm
        scheduleTime = `${hours.toString().padStart(2, "0")}:${minutes}`;
        console.log('Converted 12-hour to 24-hour:', scheduleTime);
      } else {
        // Check for HH:mm:ss.SSS format (e.g., "00:45:00.000")
        const fullTimeParts = scheduleTime.match(/^([01]\d|2[0-3]):([0-5]\d):[0-5]\d\.\d{3}$/);
        if (fullTimeParts) {
          // Extract just HH:mm
          scheduleTime = `${fullTimeParts[1]}:${fullTimeParts[2]}`;
          console.log('Converted HH:mm:ss.SSS to HH:mm:', scheduleTime);
        }
      }

      // Validate the time in HH:mm format
      if (!scheduleTime.match(/^([01]\d|2[0-3]):([0-5]\d)$/)) {
        console.log('Validation failed for time:', scheduleTime);
        helper.showToast(component, "Error", "Please provide a valid time in HH:mm format (e.g., 14:30).", "error");
        return;
      }

      console.log('Final validated scheduleTime:', scheduleTime);
    }

    component.set("v.isProcessing", true);
    const action = component.get("c.scheduleMDMProcess");
    action.setParams({
      objectName: selectedObject,
      fields: selectedFields,
      fieldThresholds: fieldThresholds,
      includeDependents: includeDependents,
      scheduleTime: scheduleTime,
      isScheduled: isScheduled,
      errorEmails: errorEmails
    });
    action.setCallback(this, function(response) {
      const state = response.getState();
      component.set("v.isProcessing", false);
      if (state === "SUCCESS") {
        if (isScheduled) {
          component.set("v.isJobScheduledForObject", true);
          component.set("v.startButtonLabel", "Terminate MDM Process");
        } else {
          component.set("v.isJobScheduledForObject", false);
          component.set("v.startButtonLabel", "Start MDM Process Now");
        }
        helper.showToast(component, "Success", isScheduled ? "MDM Process scheduled successfully!" : "MDM Schedule removed.", "success");
      } else {
        helper.showToast(component, "Error", response.getError()[0].message, "error");
      }
    });
    $A.enqueueAction(action);
  },

  removeSchedule: function(component, event, helper) {
    component.set("v.isProcessing", true);
    const action = component.get("c.removeScheduledJob");
    action.setCallback(this, function(response) {
      const state = response.getState();
      component.set("v.isProcessing", false);
      if (state === "SUCCESS") {
        component.set("v.isScheduled", false);
        component.set("v.isJobScheduledForObject", false);
        component.set("v.startButtonLabel", "Start MDM Process Now");
        helper.showToast(component, "Success", "Scheduled job removed successfully.", "success");
      } else {
        helper.showToast(component, "Error", response.getError()[0].message, "error");
      }
    });
    $A.enqueueAction(action);
  }
})