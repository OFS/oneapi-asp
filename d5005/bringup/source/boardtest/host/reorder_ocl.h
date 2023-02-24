

void ocl_device_init( cl_platform_id in_platform,
                      cl_device_id in_device,
                      cl_context in_context,
                      cl_command_queue in_queue, cl_program in_program);
void ocl_kernel_init(const char *kernel_name, const char * cl_file);
void ocl_kernel_run( int n, double *time) ;
void ocl_modify_src( int offset, unsigned val ) ;
void ocl_transfer_src( unsigned int *src, int n) ;
void ocl_transfer_index( unsigned int *index, int n) ;
void ocl_transfer_dst( unsigned int *dst, int n) ;
void ocl_transfer_dum( int n ) ;
