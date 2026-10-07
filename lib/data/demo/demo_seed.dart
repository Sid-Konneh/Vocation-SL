import '../../models/models.dart';

const demoUserId = 'demo-user';
const demoEmail = 'demo@vocationsl.app';
const demoPassword = 'Demo@2026';

AppUser buildDemoUser(DateTime now) => AppUser(
      id: demoUserId,
      fullName: 'Aminata Sesay',
      email: demoEmail,
      phone: '+232 76 123 456',
      headline: 'Software Developer · Flutter & Data',
      location: 'Freetown',
      about:
          'Developer with three years of experience building mobile and web apps for fintech and education clients in Freetown. I enjoy designing offline-first apps for users with patchy connectivity, and I mentor students at a local coding club.',
      experience: [
        Experience(
          title: 'Junior Software Developer',
          company: 'Atlantic Coders Hub',
          location: 'Freetown',
          start: DateTime(now.year - 2, 3),
          description: 'Build Flutter apps and Node.js APIs for SME clients; led the offline sync module for a savings-group app.',
        ),
        Experience(
          title: 'IT Intern',
          company: 'Western Area Teachers College',
          location: 'Freetown',
          start: DateTime(now.year - 3, 6),
          end: DateTime(now.year - 2, 2),
          description: 'Supported staff with IT issues and built a small library catalogue in Excel and Access.',
        ),
      ],
      education: [
        Education(school: 'Fourah Bay College, University of Sierra Leone', degree: 'BSc', field: 'Computer Science', startYear: now.year - 7, endYear: now.year - 3),
      ],
      skills: ['Flutter', 'Dart', 'Firebase', 'REST APIs', 'Git', 'SQL', 'Figma', 'Python'],
      certifications: [
        Certification(name: 'Associate Android Developer', issuer: 'Google', year: now.year - 1),
      ],
      languages: const [
        LanguageSkill(name: 'English', level: 'Fluent'),
        LanguageSkill(name: 'Krio', level: 'Native'),
        LanguageSkill(name: 'Temne', level: 'Conversational'),
      ],
      resume: Resume(
        id: 'r-demo',
        fileName: 'Aminata_Sesay_CV.pdf',
        sizeBytes: 248310,
        uploadedAt: now.subtract(const Duration(days: 20)),
        format: DocumentFormat.pdf,
      ),
      linkedinUrl: 'linkedin.com/in/aminata-sesay-demo',
      preferences: const JobPreferences(
        titles: ['Flutter Developer', 'Mobile Developer', 'Data Analyst'],
        industries: {Industry.technology, Industry.finance},
        locations: {'Freetown'},
        workModes: {WorkMode.hybrid, WorkMode.remote},
        employmentTypes: {EmploymentType.fullTime},
        salaryExpectation: 9000,
      ),
    );

ApplicantInfo _applicant(AppUser u) =>
    ApplicantInfo(fullName: u.fullName, email: u.email, phone: u.phone, location: u.location);

List<JobApplication> buildDemoApplications(DateTime now, AppUser u) {
  DateTime ago(int d, [int h = 0]) => now.subtract(Duration(days: d, hours: h));
  final cv = u.resume!;
  return [
    JobApplication(
      id: 'a1',
      jobId: 'j2',
      userId: u.id,
      status: ApplicationStatus.interview,
      submittedAt: ago(12),
      applicant: _applicant(u),
      resume: cv,
      coverLetter: const CoverLetter(
        id: 'cl-a1',
        kind: CoverLetterKind.written,
        text:
            'Dear Hiring Team,\n\nI am applying for the Junior Data Analyst role. In my current position I build the reporting features for our client apps, and I would love to focus fully on analysis...',
      ),
      note: 'Available to start within two weeks.',
      interviewAt: DateTime(now.year, now.month, now.day, 10).add(const Duration(days: 3)),
      employerMessage:
          'Hi Aminata, thanks for your application. We would like to invite you to a 45-minute interview at our Wilberforce studio. Please bring a laptop.',
      history: [
        StatusEvent(status: ApplicationStatus.applied, at: ago(12)),
        StatusEvent(status: ApplicationStatus.viewed, at: ago(10)),
        StatusEvent(status: ApplicationStatus.shortlisted, at: ago(6), note: 'Shortlisted by the data team.'),
        StatusEvent(status: ApplicationStatus.interview, at: ago(1), note: 'Interview scheduled.'),
      ],
    ),
    JobApplication(
      id: 'a2',
      jobId: 'j17',
      userId: u.id,
      status: ApplicationStatus.assessment,
      submittedAt: ago(9),
      applicant: _applicant(u),
      resume: cv,
      nextStepDeadline: DateTime(now.year, now.month, now.day, 17).add(const Duration(days: 2)),
      employerMessage: 'Please complete the short data-analysis exercise sent to your email before the deadline.',
      history: [
        StatusEvent(status: ApplicationStatus.applied, at: ago(9)),
        StatusEvent(status: ApplicationStatus.viewed, at: ago(8)),
        StatusEvent(status: ApplicationStatus.shortlisted, at: ago(5)),
        StatusEvent(status: ApplicationStatus.assessment, at: ago(2), note: 'Written exercise sent.'),
      ],
    ),
    JobApplication(
      id: 'a3',
      jobId: 'j3',
      userId: u.id,
      status: ApplicationStatus.viewed,
      submittedAt: ago(5),
      applicant: _applicant(u),
      resume: cv,
      history: [
        StatusEvent(status: ApplicationStatus.applied, at: ago(5)),
        StatusEvent(status: ApplicationStatus.viewed, at: ago(3)),
      ],
    ),
    JobApplication(
      id: 'a4',
      jobId: 'j4',
      userId: u.id,
      status: ApplicationStatus.applied,
      submittedAt: ago(1, 3),
      applicant: _applicant(u),
      resume: cv,
      note: 'I have been running our CI pipelines on GitHub Actions for a year.',
      history: [StatusEvent(status: ApplicationStatus.applied, at: ago(1, 3))],
    ),
    JobApplication(
      id: 'a5',
      jobId: 'j15',
      userId: u.id,
      status: ApplicationStatus.rejected,
      submittedAt: ago(25),
      applicant: _applicant(u),
      resume: cv,
      employerMessage: 'Thank you for your interest. We have chosen candidates with more classroom training experience.',
      history: [
        StatusEvent(status: ApplicationStatus.applied, at: ago(25)),
        StatusEvent(status: ApplicationStatus.viewed, at: ago(22)),
        StatusEvent(status: ApplicationStatus.rejected, at: ago(15)),
      ],
    ),
  ];
}

List<AppNotification> buildDemoNotifications(DateTime now) {
  DateTime ago(int h) => now.subtract(Duration(hours: h));
  AppNotification n(String id, NotificationType t, String title, String body, int hoursAgo,
          {bool read = false, String? job, String? app}) =>
      AppNotification(
        id: id,
        userId: demoUserId,
        type: t,
        title: title,
        body: body,
        createdAt: ago(hoursAgo),
        read: read,
        jobId: job,
        applicationId: app,
      );
  return [
    n('n1', NotificationType.newMatch, 'New job that matches your profile', 'Flutter Mobile Developer at Salone Digital Labs, Freetown', 5,
        job: 'j1'),
    n('n2', NotificationType.interview, 'Interview scheduled', 'Salone Digital Labs invited you to interview for Junior Data Analyst.', 24,
        app: 'a1', job: 'j2'),
    n('n3', NotificationType.message, 'New message from Salone Digital Labs', 'Please bring a laptop to your interview.', 23,
        app: 'a1', job: 'j2'),
    n('n4', NotificationType.statusChange, 'Assessment requested', 'Hope Bridge Initiative sent you an exercise for Monitoring & Evaluation Officer.', 48,
        app: 'a2', job: 'j17'),
    n('n5', NotificationType.savedSearch, '3 new jobs for "Remote tech roles"', 'Cloud & DevOps Engineer and 2 more', 30, read: true),
    n('n6', NotificationType.deadline, 'Closing soon: Farm Operations Supervisor', 'Applications close in 2 days.', 10, job: 'j24'),
    n('n7', NotificationType.viewed, 'Application viewed', 'Cotton Tree Finance viewed your application for IT Support Officer.', 72,
        read: true, app: 'a3', job: 'j3'),
    n('n8', NotificationType.submitted, 'Application submitted', 'Your application for Cloud & DevOps Engineer was sent.', 27,
        read: true, app: 'a4', job: 'j4'),
    n('n9', NotificationType.shortlisted, 'You were shortlisted', 'Hope Bridge Initiative shortlisted you for Monitoring & Evaluation Officer.', 120,
        read: true, app: 'a2', job: 'j17'),
    n('n10', NotificationType.statusChange, 'Application update', 'Bright Futures Education Trust has made a decision on Digital Literacy Trainer.', 360,
        read: true, app: 'a5', job: 'j15'),
  ];
}

List<SavedJob> buildDemoSavedJobs(DateTime now) => [
      SavedJob(jobId: 'j1', userId: demoUserId, savedAt: now.subtract(const Duration(hours: 3))),
      SavedJob(jobId: 'j19', userId: demoUserId, savedAt: now.subtract(const Duration(days: 1))),
      SavedJob(jobId: 'j27', userId: demoUserId, savedAt: now.subtract(const Duration(days: 2))),
    ];

List<JobAlert> buildDemoAlerts(DateTime now) => [
      JobAlert(
        id: 'al1',
        userId: demoUserId,
        name: 'Flutter jobs in Freetown',
        filter: const JobFilter(query: 'flutter', locations: {'Freetown'}),
        createdAt: now.subtract(const Duration(days: 14)),
        frequency: AlertFrequency.instant,
      ),
      JobAlert(
        id: 'al2',
        userId: demoUserId,
        name: 'Remote tech roles',
        filter: const JobFilter(industries: {Industry.technology}, workModes: {WorkMode.remote}),
        createdAt: now.subtract(const Duration(days: 30)),
      ),
    ];
