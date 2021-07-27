module.exports = {
    async create(user, clientIP, userAgent, status) {
        try {
            const detector = new DeviceDetector();
            const result = detector.detect(userAgent);
            const ipLocation = await UserService.getUserIpLocation(clientIP);
            await LoginHistoryModel.create({
                userId: user._id,
                ipLocation,
                device: result,
                status,
            });
            MailService.sendLoginEmail(
                user.email,
                ipLocation,
                result,
                user.twoFactorEnabled,
                status
            );
        } catch (error) {
            ErrorService.log('loginHistory.create', error);
            throw error;
        }
    },
    async findBy({ query, skip, limit, select, populate }) {
        try {
            if (!skip) skip = 0;

            if (!limit) limit = 10;

            if (typeof skip === 'string') {
                skip = parseInt(skip);
            }

            if (typeof limit === 'string') {
                limit = parseInt(limit);
            }

            if (!query) {
                query = {};
            }

            let logsQuery = LoginHistoryModel.find(query)
                .lean()
                .sort([['createdAt', -1]])
                .limit(limit)
                .skip(skip);

            logsQuery = await handleSelect(select, logsQuery);
            logsQuery = await handlePopulate(populate, logsQuery);

            const [logs, count] = await Promise.all([
                logsQuery,
                LoginHistoryModel.countDocuments(query),
            ]);
            const response = { logs, skip, limit, count };
            return response;
        } catch (error) {
            ErrorService.log('loginHistory.findBy', error);
            throw error;
        }
    },
};

const LoginHistoryModel = require('../models/loginIPLog');
const ErrorService = require('./errorService');
const DeviceDetector = require('node-device-detector');
const MailService = require('../services/mailService');
const UserService = require('../services/userService');
const handleSelect = require('../utils/select');
const handlePopulate = require('../utils/populate');
