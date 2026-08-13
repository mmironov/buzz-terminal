import { google } from 'googleapis';

/**
 * Read a Sheet's header row and data rows.
 *
 * Scoped to `spreadsheets.readonly` deliberately: this tool has no business
 * writing to the Sheet, and a read-only credential cannot destroy the roster
 * even if the script has a bug.
 */
export async function readSheet({ keyFile, spreadsheetId, range }) {
  const auth = new google.auth.GoogleAuth({
    keyFile,
    scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
  });
  const sheets = google.sheets({ version: 'v4', auth });

  let response;
  try {
    response = await sheets.spreadsheets.values.get({ spreadsheetId, range });
  } catch (error) {
    if (error?.code === 403) {
      throw new Error(
        `Google refused access to the Sheet (403).\n` +
          `Share the Sheet with the service account's email address (Viewer is enough),\n` +
          `and check that the Google Sheets API is enabled on the project.`
      );
    }
    if (error?.code === 404) {
      throw new Error(`No Sheet with id "${spreadsheetId}", or the range "${range}" does not exist.`);
    }
    throw error;
  }

  const values = response.data.values ?? [];
  if (values.length === 0) {
    throw new Error(`Range "${range}" is empty — nothing to import.`);
  }

  const [header, ...rows] = values;
  // Trailing blank rows are normal in a hand-maintained Sheet.
  const populated = rows.filter((cells) =>
    cells.some((cell) => String(cell ?? '').trim() !== '')
  );

  return { header, rows: populated };
}
