({
	doInit: function (component, event, helper) {
	},

	doRefresh: function (component, event, helper) {
	},

	handleClick: function (component, event, helper) {
		const CONSTANTS = component.get('v.xdoToolTrackingEventConstants');
		const dataset = {
			domEvent: event.type,
			version: CONSTANTS.VERSION,
			type: 'reporting',
			event: 'conversion',
			action: 'Sample Aura - Track event',
			minutesSaved: .5,
			value: component.get('v.exampleValue'),
			once: false
		};

		component.find('xdoToolTrackingEventHandler')
			.track(CONSTANTS.COMPONENT_NAME, dataset);
	}
})