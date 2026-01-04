<?php
$CONFIG = array (
    'session_save_handler' => 'files',
    'session_save_path' => __DIR__ . '/../data/sessions',
);

// Force PHP to use files for session storage (overrides Railway entrypoint)
ini_set('session.save_handler', 'files');
ini_set('session.save_path', __DIR__ . '/../data/sessions');
