import ApiService from '../Utils/apiService';

import { run as runScript } from '../Utils/scriptSandbox';

// it collects all monitors then ping them one by one to store their response
export default {
    run: async (monitor: $TSFixMe) => {
        if (monitor && monitor.type === 'script') {
            if (monitor.data.script) {
                const code: $TSFixMe = monitor.data.script; // redundant now but may be expanded in future
                const {
                    success,
                    message,
                    errors,
                    status,
                    executionTime,
                    consoleLogs,
                } = await runScript(code, true);

                // normalize response
                const resp: $TSFixMe = {
                    success,
                    statusText: status,
                    error: success ? undefined : message + ': ' + errors,
                    executionTime,
                    consoleLogs,
                };

                await ApiService.ping(monitor._id, {
                    monitor,
                    resp,
                });
            }
        }
    },
};
