<?php
/**
 * @author Amin Mahmoudi (MasterkinG)
 * @copyright    Copyright (c) 2019 - 2021, MasterkinG32. (https://masterking32.com)
 * @link    https://masterking32.com
 * @Description : It's not masterking32 framework !
 **/

use Medoo\Medoo;

class database  
{  
    public static $auth;  
    public static $chars;  
  
    public static function db_connect()  
    {    
        self::$auth = new Medoo([  
            'database_type' => 'mysql',  
            'database_name' => get_config('db_auth_dbname'), 
            // 'server' => get_config('db_auth_host'),
            'server' => get_config('db_auth_host'), 'port' => get_config('db_auth_port'),
            'username' => get_config('db_auth_user'),  
            'password' => get_config('db_auth_pass'),  
            'charset' => 'utf8',  
            'collation' => 'utf8_general_ci'
            // 'port' => get_config('db_auth_port')
        ]);  
  
        foreach (get_config("realmlists") as $realm) {  
            if (!empty($realm["realmid"]) && !empty($realm["db_name"]) && !empty($realm["db_user"]) && !empty($realm["db_pass"]) && !empty($realm["db_host"])) {
                self::$chars[$realm["realmid"]] = new Medoo([  
                    'database_type' => 'mysql',  
                    'database_name' => $realm["db_name"],  
                    'server' => $realm['db_host'], 'port' => $realm['db_port'],
                    // 'server' => $realm["db_host"],
                    'username' => $realm["db_user"],  
                    'password' => $realm["db_pass"],  
                    'charset' => 'utf8',  
                    'collation' => 'utf8_general_ci'
                    // 'port' => $realm["db_port"]
                ]);  
            } else {  
                die("Missing char database required field.");  
            }  
        }  
    }  
}