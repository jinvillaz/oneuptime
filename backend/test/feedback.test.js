process.env.PORT = 3020;
var expect = require('chai').expect;
var userData = require('./data/user');
var chai = require('chai');
chai.use(require('chai-http'));
var app = require('../server');
var mailParser = require('mailparser').simpleParser;

var request = chai.request.agent(app);
var { createUser } = require('./utils/userSignUp');
var UserService = require('../backend/services/userService');
var FeedbackService = require('../backend/services/feedbackService');
var ProjectService = require('../backend/services/projectService');
var VerificationTokenModel = require('../backend/models/verificationToken');
var AirtableService = require('../backend/services/airtableService');

var token, projectId, userId, airtableId, emailContent;
var { imap, openBox, feedbackEmailContent } = require('./utils/mail');

describe('Feedback API', function () {
    this.timeout(50000);

    before(function (done) {
        this.timeout(40000);
        createUser(request, userData.user, function(err, res) {
            let project = res.body.project;
            projectId = project._id;
            userId = res.body.id;
            airtableId = res.body.airtableId;

            VerificationTokenModel.findOne({ userId }, function (err, verificationToken) {
                request.get(`/user/confirmation/${verificationToken.token}`).redirects(0).end(function () {
                    request.post('/user/login').send({
                        email: userData.user.email,
                        password: userData.user.password
                    }).end(function (err, res) {
                        token = res.body.tokens.jwtAccessToken;
                        done();
                    });
                });
            });
        });
    });

    after(async function () {
        await UserService.hardDeleteBy({ email: { $in: [userData.user.email, userData.newUser.email, userData.anotherUser.email] } });
        await ProjectService.hardDeleteBy({ _id: projectId }, userId);
        await AirtableService.deleteUser(airtableId);
    });

    it('should create feedback and check the sent emails to fyipe team and user', function (done) {

        var authorization = `Basic ${token}`;
        var testFeedback = {
            feedback: 'test feedback',
            page: 'test page'
        };
        request.post(`/feedback/${projectId}`).set('Authorization', authorization).send(testFeedback).end(function (err, res) {
            expect(res).to.have.status(200);
            FeedbackService.hardDeleteBy({ _id: res.body._id });
            AirtableService.deleteFeedback(res.body.airtableId);
            imap.once('ready', function () {
                openBox(function (err, box) {
                    if (err) throw err;
                    var seq =  box.messages.total;
                    var f = imap.seq.fetch(`${seq}:${seq}`, {
                        bodies: [''],
                        struct: true
                    });
                    f.on('message', function (msg) {
                        msg.on('body', function (stream) {
                            mailParser(stream, {}, async function (err, parsedMail) {
                                if (parsedMail.subject === 'Thank you for your feedback!') {
                                    emailContent = (parsedMail.text);
                                    expect(emailContent).to.be.equal(feedbackEmailContent);
                                }
                            });
                        });
                    });
                    f.once('end', function () {
                        imap.end();
                        done();
                    });
                });
            });
            imap.connect();
        });
    });
});