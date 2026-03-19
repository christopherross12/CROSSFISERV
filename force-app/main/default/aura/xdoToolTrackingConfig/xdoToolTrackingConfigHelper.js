({
    trackEvent : function(component) {
        const CONSTANTS = component.get('v.xdoToolTrackingEventConstants');
        const pageContext = component.get('v.pageContext')
        const dataset = {
            domEvent: 'load',
            version: CONSTANTS.VERSION,
            source: component.get('v.source'),
            once: component.get('v.once'),

            event: 'conversion',
            elementType: 'Link',
            elementLabel: 'Download',
            elementValue: 'url of file',
            systemUp: 'true',
            responseTime: 6969,

            action: pageContext,
            minutesSaved: component.get('v.minutesSaved'),
            value: ''
        };

        if (!component.get('v.hasRendered')) {
            if (pageContext != '') {
                component.find('xdoToolTrackingEventHandler')
                    .track(CONSTANTS.COMPONENT_NAME, dataset);
            }
            component.set('v.hasRendered', true);
        }
    }
})