function fp_build_session_key_from_folder(rootDir)
% BUILD_SESSION_KEY_FROM_FOLDER
% Backward-compatible wrapper for fp_build_session_key_from_folder.

    if nargin < 1
        fp_build_session_key_from_folder();
    else
        fp_build_session_key_from_folder(rootDir);
    end
end
