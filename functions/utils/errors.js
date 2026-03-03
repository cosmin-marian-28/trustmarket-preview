const functions = require('firebase-functions');

/**
 * Handle errors consistently across functions
 * @param {Error} error - The error to handle
 * @param {string} label - Context label for logging
 * @throws {HttpsError} - Always throws formatted error
 */
function handleError(error, label = 'Error') {
  console.error(`❌ ${label}:`, error.message);
  
  // If already an HttpsError, just throw it
  if (error instanceof functions.https.HttpsError) {
    throw error;
  }
  
  // Convert to HttpsError
  throw new functions.https.HttpsError(
    'internal',
    error.message || 'An unexpected error occurred'
  );
}

module.exports = {
  handleError
};
