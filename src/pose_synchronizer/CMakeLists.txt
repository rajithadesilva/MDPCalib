cmake_minimum_required(VERSION 3.0.2)
project(pose_synchronizer)

## Compile as C++11, supported in ROS Kinetic and newer
add_compile_options(-std=c++17 -Wall)

# Get the information about this package's buildtime dependencies
find_package(catkin REQUIRED COMPONENTS
    roscpp
    rospy
    rosbag
    std_msgs
    nav_msgs
    geometry_msgs
    sensor_msgs
    message_filters
    tf2_geometry_msgs
    tf2_sensor_msgs
    calib_msgs
    cv_bridge
)

catkin_package(
  CATKIN_DEPENDS
    roscpp
    rospy
    rosbag
    std_msgs
    nav_msgs
    geometry_msgs
    sensor_msgs
    message_filters
    tf2_geometry_msgs
    tf2_sensor_msgs
    calib_msgs
    cv_bridge
)

include_directories(
    ${catkin_INCLUDE_DIRS}
    include
)

set(HEADER_FILES
    include/${PROJECT_NAME}/pose_synchronizer.h
)

set(SOURCE_FILES
    src/pose_synchronizer.cpp
    src/node.cpp
)

add_executable(${PROJECT_NAME} ${SOURCE_FILES} ${HEADER_FILES})
target_link_libraries(${PROJECT_NAME}
  ${catkin_LIBRARIES}
  yaml-cpp
)

catkin_install_python(PROGRAMS
  scripts/blt_camera_adapter.py
  scripts/publish_gt_from_tf.py
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)
