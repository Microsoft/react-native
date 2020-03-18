import winston from 'winston';
import fs_path from 'path'; // TODO

// Suitable for developments.. may not be when running in the CI/Publish machines.
// const getLogDirectoryDev = () => {
//   const loggerSourcePath = __dirname;
//   const loggerParentDir = fs_path.resolve(loggerSourcePath, '..');
//   const logDirBase = fs_path.resolve(loggerParentDir, 'logs');
//   return fs_path.resolve(logDirBase, `${Date.now()}`);
// };

// const logDirectory = getLogDirectoryDev();

winston.add(
  new winston.transports.Console({
    handleExceptions: true,
    level: 'info',
  }),
);

function setLogFolder(logFolder: string) {
  // logFolder = fs_path.resolve(logFolder, `${Date.now()}`);

  winston.add(
    new winston.transports.File({
      filename: 'error.log',
      level: 'error',
      dirname: logFolder,
    }),
  );
  winston.add(
    new winston.transports.File({
      filename: 'warn.log',
      level: 'warn',
      dirname: logFolder,
    }),
  );
  winston.add(
    new winston.transports.File({
      filename: `all.log`,
      dirname: logFolder,
    }),
  );
  winston.exceptions.handle(
    new winston.transports.File({
      filename: 'exceptions.log',
      dirname: logFolder,
    }),
  );
}

function info(prefix: string, message: string) {
  // error(prefix, message);
  winston.info(`${prefix} - ${message}`);
}

function verbose(prefix: string, message: string) {
  // error(prefix, message);
  winston.verbose(`${prefix} - ${message}`);
}

const errors: string[] = [];
function error(prefix: string, message: string) {
  const message2 = `${prefix} - ${message}`;
  errors.push(message2);
  winston.error(message2);
}

function warn(prefix: string, message: string) {
  // error(prefix, message);
  winston.warn(`${prefix} - ${message}`);
}

function queryErrors(resultCallback: (error: string[]) => void) {
  // winston.error('Done', () => {
  //   const options: winston.QueryOptions = {
  //     // //from: new Date() - 24 * 60 * 60 * 1000,
  //     until: new Date(),
  //     limit: 500,
  //     start: 0,
  //     order: 'desc',
  //     fields: ['message', 'level'],
  //   };
  //   winston.query(options, (err, results) => {
  //     if (err) {
  //       /* TODO: handle me */
  //       throw err;
  //     }
  //     const errors: string[] = [];
  //     results.file.forEach((element: {level: string; message: string}) => {
  //       if (element.level === 'error') {
  //         // tslint:disable-next-line:no-console
  //         console.log(element.message);
  //         errors.push(element.message);
  //       }
  //     });
  //     resultCallback(errors);
  //   });
  // });
  resultCallback(errors);
}

const log = {queryErrors, setLogFolder, error, warn, info, verbose};
export {log};